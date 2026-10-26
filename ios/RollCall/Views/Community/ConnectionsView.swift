//
//  ConnectionsView.swift
//  RollCall
//
//  "Connections": everyone in your community as floating bubbles, with a
//  line between each volunteer buddy and the neighbor they check on. It's
//  easy to see who's covered and who still needs someone.
//
//  The bubbles are a small physics simulation, stepped about 60 times a second:
//    * every bubble gently pushes the others away, so nobody overlaps
//    * each buddy line works like a spring, pulling the pair together
//    * a soft pull toward the middle keeps the group on screen
//    * a little drift makes them float, and friction calms them down
//  Drag a bubble and its buddies follow, then everything settles. Tap one
//  to see the name (tap the name for their profile). Press and hold one to
//  pop it; it comes back after 5 seconds.
//
//  Rings around a bubble:  orange = no buddy yet,  gold = community admin,
//  blue with "NEW" = joined recently,  dashed gray = away from home.
//
//  ConnectionsWeb is the web itself. The Community tab shows a small,
//  look-only preview of it; ConnectionsView is the full screen.
//  The bubbles use Liquid Glass (iOS 26 and later), the only place in the
//  app that does.
//

import SwiftUI

/// How recently someone joined to count as "new". (A week in real use. For
/// the demo, the last hour, so new members stand out right away.)
let newMemberWindow: TimeInterval = 60 * 60

enum ConnectionsFilter: Hashable, CaseIterable {
    case everyone, needsBuddy, hasBuddy, volunteers, away, new

    var title: String {
        switch self {
        case .everyone: String(localized: "Everyone")
        case .needsBuddy: String(localized: "No buddy yet")
        case .hasBuddy: String(localized: "Has a buddy")
        case .volunteers: String(localized: "Volunteers")
        case .away: String(localized: "Away")
        case .new: String(localized: "New")
        }
    }

    var symbol: String {
        switch self {
        case .everyone: "person.3.fill"
        case .needsBuddy: "person.fill.questionmark"
        case .hasBuddy: "person.2.fill"
        case .volunteers: "hand.raised.fill"
        case .away: "suitcase.fill"
        case .new: "sparkles"
        }
    }

    func matches(_ member: CommunityMember) -> Bool {
        switch self {
        case .everyone: true
        case .needsBuddy: !member.hasBuddy
        case .hasBuddy: member.hasBuddy
        case .volunteers: member.checksOn > 0
        case .away: member.awayFromHome
        case .new: member.isNew
        }
    }
}

extension CommunityMember {
    var isNew: Bool { Date.now.timeIntervalSince(since) < newMemberWindow }
}

// MARK: - The full screen

struct ConnectionsView: View {
    let members: [CommunityMember]
    let pairs: [BuddyPair]
    @State private var filter: ConnectionsFilter = .everyone
    @State private var openPerson: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var brand
    @Environment(\.onBrand) private var onBrand

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                ConnectionsWeb(members: members, pairs: pairs, filter: filter, interactive: true,
                               bubbleSize: 78, onOpenProfile: { openPerson = $0 })
                legend
            }
            .sheetPage()
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeConnections")
                }
                .flat()
            }
            .sheet(item: $openPerson) { id in PersonProfileView(personID: id).sheetBrand() }
        }
    }

    /// Chips like the map's filters: highlight part of the community.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(ConnectionsFilter.allCases, id: \.self) { option in
                    let isOn = filter == option
                    let count = members.filter(option.matches).count
                    Button {
                        withAnimation(.snappy) { filter = option }
                    } label: {
                        Label("\(option.title) \(count)", systemImage: option.symbol)
                            .font(.app(.subheadline).weight(.semibold))
                            .padding(.horizontal, Spacing.m)
                            .frame(minHeight: 40)
                            .foregroundStyle(isOn ? onBrand : Color.primary)
                            .background(isOn ? brand : Color.paperRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.l) {
                legendItem(Capsule().fill(Color(.systemGreen)).frame(width: 22, height: 3), "Checks on")
                legendItem(ring(Color(.systemOrange)), "No buddy")
                legendItem(ring(Color(.systemYellow)), "Admin")
            }
            HStack(spacing: Spacing.l) {
                legendItem(ring(Color(.systemBlue)), "New")
                legendItem(Circle().strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    .frame(width: 14, height: 14), "Away")
                Spacer()
                Text("Hold a bubble to pop it").font(.app(.footnote)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .accessibilityElement(children: .combine)
    }

    private func ring(_ color: Color) -> some View {
        Circle().strokeBorder(color, lineWidth: 2.5).frame(width: 14, height: 14)
    }

    private func legendItem(_ mark: some View, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) { mark; Text(text).font(.app(.footnote)) }
    }
}

// MARK: - The web

/// The bubbles and lines. With `interactive` off it's a look-only preview.
struct ConnectionsWeb: View {
    let members: [CommunityMember]
    let pairs: [BuddyPair]
    var filter: ConnectionsFilter = .everyone
    var interactive = true
    var bubbleSize: CGFloat = 78
    var onOpenProfile: ((Int) -> Void)? = nil

    @State private var simulation: BubbleSimulation
    @State private var selected: Int?
    @State private var popped: Set<Int> = []
    @State private var canvasSize: CGSize = .zero

    init(members: [CommunityMember], pairs: [BuddyPair], filter: ConnectionsFilter = .everyone,
         interactive: Bool = true, bubbleSize: CGFloat = 78, onOpenProfile: ((Int) -> Void)? = nil) {
        self.members = members
        self.pairs = pairs
        self.filter = filter
        self.interactive = interactive
        self.bubbleSize = bubbleSize
        self.onOpenProfile = onOpenProfile
        _simulation = State(initialValue: BubbleSimulation(ids: members.map(\.userId),
                                                           links: pairs.map { ($0.volunteerId, $0.residentId) },
                                                           scale: bubbleSize / 78))
    }

    var body: some View {
        ZStack {
            links
            ForEach(members) { member in bubble(member) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { selected = nil } }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .task {
            while !Task.isCancelled {
                simulation.step(to: .now, in: canvasSize)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .allowsHitTesting(interactive)
    }

    /// The buddy lines, drawn under the bubbles. A small dot travels along
    /// each one, from the volunteer to the person they check on.
    private var links: some View {
        Canvas { context, _ in
            let time = simulation.time
            for (from, to) in simulation.links where !popped.contains(from) && !popped.contains(to) {
                guard let a = simulation.position(of: from), let b = simulation.position(of: to) else { continue }
                let lit = isHighlighted(from) && isHighlighted(to)
                var line = Path()
                line.move(to: a)
                line.addLine(to: b)
                context.stroke(line, with: .color(Color(.systemGreen).opacity(lit ? 0.75 : 0.15)),
                               style: StrokeStyle(lineWidth: lit ? 3 : 2, lineCap: .round))
                if lit {
                    let t = CGFloat((time * 0.35).truncatingRemainder(dividingBy: 1))
                    let dot = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)),
                                 with: .color(Color(.systemGreen)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func isHighlighted(_ id: Int) -> Bool {
        guard let member = members.first(where: { $0.userId == id }) else { return false }
        return filter.matches(member)
    }

    @ViewBuilder
    private func bubble(_ member: CommunityMember) -> some View {
        if let point = simulation.position(of: member.userId) {
            let lit = filter.matches(member)
            let isSelected = selected == member.userId
            let isPopped = popped.contains(member.userId)
            VStack(spacing: Spacing.s) {
                ZStack {
                    BubbleFace(member: member, size: bubbleSize)
                        .scaleEffect(isPopped ? 1.6 : isSelected ? 1.12 : (simulation.dragging == member.userId ? 1.08 : 1))
                        .opacity(isPopped ? 0 : 1)
                    if isPopped { PopBurst(size: bubbleSize) }
                }
                if isSelected && !isPopped {
                    Button { onOpenProfile?(member.userId) } label: {
                        HStack(spacing: 6) {
                            Text(verbatim: member.name).font(.app(.subheadline).weight(.semibold))
                            Image(systemName: "chevron.right").font(.app(.caption).weight(.bold))
                        }
                        .padding(.horizontal, Spacing.m)
                        .frame(minHeight: 36)
                        .foregroundStyle(Color.primary)
                        .glassCapsule()
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .accessibilityIdentifier("openBubbleProfile")
                }
            }
            .opacity(lit ? 1 : 0.3)
            .position(x: point.x, y: point.y + (isSelected ? 22 : 0))
            .zIndex(isSelected || simulation.dragging == member.userId ? 1 : 0)
            .animation(.spring(duration: 0.3), value: isSelected)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in simulation.drag(member.userId, to: value.location) }
                    .onEnded { value in simulation.release(member.userId, velocity: value.velocity) }
            )
            .simultaneousGesture(TapGesture().onEnded {
                guard !isPopped else { return }
                withAnimation(.snappy) { selected = selected == member.userId ? nil : member.userId }
            })
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in pop(member.userId) })
            .sensoryFeedback(.selection, trigger: isSelected)
            .sensoryFeedback(.impact(weight: .medium), trigger: isPopped)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(member.name)
            .accessibilityValue(member.hasBuddy ? "Has a buddy" : "No buddy yet")
            .accessibilityHint("Shows their name. Tap the name to open their profile.")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("bubble_\(member.userId)")
        }
    }

    /// Pop a bubble. It floats back 5 seconds later.
    private func pop(_ id: Int) {
        if selected == id { selected = nil }
        withAnimation(.easeOut(duration: 0.25)) { _ = popped.insert(id) }
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { _ = popped.remove(id) }
        }
    }
}

/// A few droplets flying out, where a bubble just popped.
struct PopBurst: View {
    let size: CGFloat
    @State private var out = false

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) / 8 * 2 * .pi
                Circle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .offset(x: out ? cos(angle) * size * 0.75 : 0, y: out ? sin(angle) * size * 0.75 : 0)
                    .opacity(out ? 0 : 1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.45)) { out = true } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One bubble: the person's picture inside a glass sphere, with a little
/// room around it so they look like they're inside, and rings for what
/// stands out about them.
struct BubbleFace: View {
    let member: CommunityMember
    let size: CGFloat

    var body: some View {
        Avatar(url: member.photoURL, name: member.name, size: size - size * 0.15)
            .frame(width: size, height: size)
            .glassBubble()
            .overlay { rings }
            .overlay(alignment: .bottomTrailing) {
                if member.checksOn > 0 {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: size * 0.14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: size * 0.28, height: size * 0.28)
                        .background(Color(.systemTeal), in: Circle())
                        .offset(x: 2, y: 2)
                }
            }
            .overlay(alignment: .top) {
                if member.isNew {
                    Text("NEW")
                        .font(.system(size: max(9, size * 0.12), weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(.systemBlue), in: Capsule())
                        .offset(y: -size * 0.08)
                }
            }
    }

    /// Rings stack outward: no buddy, admin, new, away.
    private var rings: some View {
        let colors: [(Bool, Color, Bool)] = [
            (!member.hasBuddy, Color(.systemOrange), false),
            (member.isAdmin, Color(.systemYellow), false),
            (member.isNew, Color(.systemBlue), false),
            (member.awayFromHome, Color.secondary, true),
        ]
        let shown = colors.filter(\.0)
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, ring in
                Circle()
                    .strokeBorder(ring.1.opacity(0.95), style: StrokeStyle(lineWidth: 2.5, dash: ring.2 ? [4, 3] : []))
                    .padding(-CGFloat(index) * 4.5)
            }
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26 and later (it bends and shines as you touch
    /// it), a frosted look before that.
    @ViewBuilder
    func glassBubble() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.background(.ultraThinMaterial, in: Circle())
        }
    }

    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// MARK: - The physics

/// Where every bubble is and how fast it's moving. `step` moves them all a
/// tiny bit forward in time; SwiftUI redraws after every step.
@Observable
final class BubbleSimulation {
    struct Node {
        var position: CGPoint
        var velocity: CGVector = .zero
        let phase: Double   // so each bubble drifts a little differently
    }

    let links: [(Int, Int)]
    private(set) var nodes: [Int: Node] = [:]
    private(set) var dragging: Int?
    private(set) var time: Double = 0
    @ObservationIgnored private var lastDate: Date?
    @ObservationIgnored private var size: CGSize = .zero

    // The forces, tuned by feel.
    private let scale: CGFloat                  // 1 for full-size bubbles, smaller for the preview
    private var repulsion: CGFloat { 9_000 * scale * scale }   // how hard bubbles push apart
    private var springLength: CGFloat { 120 * scale }          // a buddy line's relaxed length
    private let springStrength: CGFloat = 0.035
    private let centerPull: CGFloat = 0.008
    private let friction: CGFloat = 0.86        // each step keeps 86% of the speed
    private let drift: CGFloat = 0.12

    init(ids: [Int], links: [(Int, Int)], scale: CGFloat = 1) {
        self.links = links
        self.scale = scale
        // Start in a loose circle; the forces sort them out from there.
        for (index, id) in ids.enumerated() {
            let angle = Double(index) / Double(max(ids.count, 1)) * 2 * .pi
            nodes[id] = Node(position: CGPoint(x: 0.5 + 0.3 * cos(angle), y: 0.5 + 0.3 * sin(angle)),
                             phase: Double(index) * 1.7)
        }
    }

    func position(of id: Int) -> CGPoint? { nodes[id]?.position }

    func step(to date: Date, in size: CGSize) {
        guard size.width > 0 else { return }
        if self.size == .zero {
            // The first time: turn the 0...1 starting spots into points.
            for id in nodes.keys {
                nodes[id]!.position = CGPoint(x: nodes[id]!.position.x * size.width,
                                              y: nodes[id]!.position.y * size.height)
            }
        }
        self.size = size
        let dt = min(date.timeIntervalSince(lastDate ?? date), 1.0 / 30)
        lastDate = date
        time += dt
        guard dt > 0 else { return }

        let ids = Array(nodes.keys)
        var force: [Int: CGVector] = [:]
        // 1. Everyone pushes everyone else away (stronger up close).
        for (i, a) in ids.enumerated() {
            for b in ids[(i + 1)...] {
                let pa = nodes[a]!.position, pb = nodes[b]!.position
                var dx = pa.x - pb.x, dy = pa.y - pb.y
                var distance2 = dx * dx + dy * dy
                if distance2 < 1 { dx = 1; dy = 0; distance2 = 1 }
                let distance = sqrt(distance2)
                let push = repulsion / distance2
                force[a, default: .zero].dx += dx / distance * push
                force[a, default: .zero].dy += dy / distance * push
                force[b, default: .zero].dx -= dx / distance * push
                force[b, default: .zero].dy -= dy / distance * push
            }
        }
        // 2. Buddy lines pull their two people toward a comfortable distance.
        for (a, b) in links {
            guard let pa = nodes[a]?.position, let pb = nodes[b]?.position else { continue }
            let dx = pb.x - pa.x, dy = pb.y - pa.y
            let distance = max(sqrt(dx * dx + dy * dy), 1)
            let pull = (distance - springLength) * springStrength
            force[a, default: .zero].dx += dx / distance * pull
            force[a, default: .zero].dy += dy / distance * pull
            force[b, default: .zero].dx -= dx / distance * pull
            force[b, default: .zero].dy -= dy / distance * pull
        }
        // 3. Move everyone (except the bubble being dragged).
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let margin: CGFloat = 44 * scale
        for id in ids where id != dragging {
            var node = nodes[id]!
            var f = force[id] ?? .zero
            f.dx += (center.x - node.position.x) * centerPull + CGFloat(sin(time * 0.7 + node.phase)) * drift
            f.dy += (center.y - node.position.y) * centerPull + CGFloat(cos(time * 0.6 + node.phase)) * drift
            node.velocity = CGVector(dx: (node.velocity.dx + f.dx) * friction, dy: (node.velocity.dy + f.dy) * friction)
            node.position.x = min(max(node.position.x + node.velocity.dx * dt * 60, margin), size.width - margin)
            node.position.y = min(max(node.position.y + node.velocity.dy * dt * 60, margin), size.height - margin)
            nodes[id] = node
        }
    }

    func drag(_ id: Int, to point: CGPoint) {
        dragging = id
        nodes[id]?.position = point
        nodes[id]?.velocity = .zero
    }

    /// Let go: the bubble keeps a bit of the fling, then the forces take over.
    func release(_ id: Int, velocity: CGSize) {
        dragging = nil
        nodes[id]?.velocity = CGVector(dx: velocity.width / 120, dy: velocity.height / 120)
    }
}
