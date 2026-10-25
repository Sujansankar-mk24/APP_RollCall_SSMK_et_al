//
//  RecapCarousel.swift
//  RollCall
//
//  The Weekly Recap: neighborhood photos as a stacked deck, like Locket.
//  Swipe the top card left or right (or tap it) to see the next one. Each
//  card shows who posted it in bold, with their caption under it, a
//  "Pinned" tag if the admin pinned it, and the emoji stickers people added.
//  Photos disappear after a week unless the admin pins them (pinned ones
//  come first). The admin pins, unpins and removes from the "..." menu.
//

import SwiftUI

struct RecapCarousel: View {
    let photos: [RecapPhoto]
    /// The admin sees a "..." menu on each card.
    var isAdmin = false
    /// Members can add emoji stickers.
    var canReact = false
    var onAction: ((RecapPhoto, RecapMenuAction) -> Void)? = nil
    var onReact: ((RecapPhoto, String) -> Void)? = nil

    @State private var current = 0
    @State private var drag: CGSize = .zero
    @State private var showsStickers = false

    enum RecapMenuAction { case pin, unpin, remove }

    private static let height: CGFloat = 440

    var body: some View {
        if photos.isEmpty {
            emptyCard
        } else {
            VStack(spacing: Spacing.m) {
                ZStack {
                    // Up to two cards peek out from behind the top one.
                    ForEach(Array(visibleIndices.reversed()), id: \.self) { index in
                        card(photos[index], depth: depth(of: index))
                    }
                }
                .frame(height: Self.height)
                .frame(maxWidth: .infinity)
                if canReact, let photo = photos[safe: current] { stickerBar(photo) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("weeklyRecap")
            .onChange(of: photos.count) { current = min(current, max(photos.count - 1, 0)) }
        }
    }

    // MARK: - The deck

    private var visibleIndices: [Int] {
        (0..<min(3, photos.count)).map { (current + $0) % photos.count }
    }

    private func depth(of index: Int) -> Int {
        (index - current + photos.count) % photos.count
    }

    private func card(_ photo: RecapPhoto, depth: Int) -> some View {
        let isTop = depth == 0
        // Cards behind are a little smaller, lower and tilted, like a real stack.
        let tilts: [Double] = [0, -3.5, 3]
        return RecapCard(photo: photo, index: photos.firstIndex(of: photo).map { $0 + 1 } ?? 1, total: photos.count,
                         isAdmin: isAdmin && isTop, onAction: onAction)
            .frame(height: Self.height - 24)
            .scaleEffect(1 - CGFloat(depth) * 0.04)
            .rotationEffect(.degrees(isTop ? Double(drag.width) / 22 : tilts[min(depth, 2)]))
            .offset(x: isTop ? drag.width : 0, y: CGFloat(depth) * -10 + (isTop ? drag.height / 6 : 0))
            .zIndex(Double(3 - depth))
            .allowsHitTesting(isTop)
            .gesture(isTop ? swipe : nil)
            .onTapGesture { if isTop { advance(by: 1) } }
            .animation(.spring(duration: 0.35, bounce: 0.25), value: current)
            .accessibilityHidden(!isTop)
    }

    private var swipe: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let far = abs(value.translation.width) > 90 || abs(value.predictedEndTranslation.width) > 220
                if far {
                    // Fling the card off, then bring the next one up.
                    withAnimation(.easeOut(duration: 0.18)) { drag.width = value.translation.width > 0 ? 500 : -500 }
                    Task {
                        try? await Task.sleep(for: .milliseconds(180))
                        drag = .zero
                        advance(by: value.translation.width > 0 ? -1 : 1)
                    }
                } else {
                    withAnimation(.spring(duration: 0.3)) { drag = .zero }
                }
            }
    }

    private func advance(by step: Int) {
        guard photos.count > 1 else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
            current = (current + step + photos.count) % photos.count
        }
    }

    // MARK: - Stickers

    private func stickerBar(_ photo: RecapPhoto) -> some View {
        HStack(spacing: Spacing.s) {
            ForEach(RecapPhoto.stickers, id: \.self) { emoji in
                let reaction = photo.reactions.first { $0.emoji == emoji }
                Button { onReact?(photo, emoji) } label: {
                    HStack(spacing: 3) {
                        Text(verbatim: emoji).font(.title3)
                        if let reaction { Text("\(reaction.count)").font(.caption.weight(.bold)).monospacedDigit() }
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 40)
                    .background(reaction?.mine == true ? Color.primary.opacity(0.16) : Color.paperRaised, in: Capsule())
                    .overlay(Capsule().strokeBorder(reaction?.mine == true ? Color.primary.opacity(0.4) : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: reaction?.mine)
                .accessibilityLabel("React with \(emoji)")
                .accessibilityValue(reaction.map { "\($0.count)" } ?? "")
                .accessibilityAddTraits(reaction?.mine == true ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recapStickers")
    }

    private var emptyCard: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "photo.stack")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No photos this week yet")
                .font(.sheetHeading)
            Text("Share what's happening in the neighborhood: a cleanup, a block party, a storm you got through together.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, minHeight: 220)
        .paperCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weeklyRecapEmpty")
    }
}

/// One photo in the deck: the picture with rounded corners, "1 / 3" and a
/// Pinned tag at the top, and at the bottom the poster's name in bold, their
/// caption, and the stickers people added.
private struct RecapCard: View {
    let photo: RecapPhoto
    let index: Int
    let total: Int
    let isAdmin: Bool
    let onAction: ((RecapPhoto, RecapCarousel.RecapMenuAction) -> Void)?

    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        // The photo fills the card. It sits in an overlay so a wide photo
        // can't stretch the card (and the whole page) past the screen edge.
        Color.primary.opacity(0.08)
            .overlay {
                AsyncImage(url: photo.imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    LoadingLogo(size: 48)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
        .overlay {
            LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.22),
                                   .init(color: .clear, location: 0.55), .init(color: .black.opacity(0.7), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(shape)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) { topRow }
        .overlay(alignment: .bottomLeading) { bottomRow }
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(photo.caption.isEmpty ? "Photo by \(photo.uploaderName)" : "\(photo.uploaderName): \(photo.caption)")
        .accessibilityHint("Swipe or tap for the next photo")
    }

    private var topRow: some View {
        HStack(spacing: Spacing.s) {
            if photo.pinned {
                Label("Pinned", systemImage: "pin.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).frame(minHeight: 28)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            Spacer()
            Text("\(index) / \(total)")
                .font(.caption.weight(.bold)).monospacedDigit()
                .padding(.horizontal, 10).frame(minHeight: 28)
                .background(.black.opacity(0.45), in: Capsule())
            if isAdmin {
                Menu {
                    if photo.pinned {
                        Button("Unpin", systemImage: "pin.slash") { onAction?(photo, .unpin) }
                    } else {
                        Button("Pin (keep it past the week)", systemImage: "pin") { onAction?(photo, .pin) }
                    }
                    Button("Remove", systemImage: "trash", role: .destructive) { onAction?(photo, .remove) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: minimumTapSize, height: minimumTapSize)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .accessibilityLabel("Photo options")
                .accessibilityIdentifier("recapPhotoMenu")
            }
        }
        .foregroundStyle(.white)
        .padding(Spacing.m)
    }

    private var bottomRow: some View {
        HStack(alignment: .bottom, spacing: Spacing.m) {
            Avatar(url: photo.uploaderPhotoURL, name: photo.uploaderName, size: 40)
                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: photo.uploaderName).font(.headline.weight(.bold))
                if !photo.caption.isEmpty {
                    Text(verbatim: photo.caption).font(.subheadline).lineLimit(3)
                }
                Text(photo.createdAt, format: .relative(presentation: .named))
                    .font(.caption).opacity(0.8)
            }
            Spacer(minLength: 0)
            // The stickers people added, piled up like on Locket.
            HStack(spacing: -8) {
                ForEach(photo.reactions.prefix(4), id: \.emoji) { reaction in
                    Text(verbatim: reaction.emoji)
                        .font(.title2)
                        .padding(4)
                        .background(.white.opacity(0.9), in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 3)
                }
            }
            .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(Spacing.l)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
