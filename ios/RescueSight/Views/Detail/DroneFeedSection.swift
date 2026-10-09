//
//  DroneFeedSection.swift
//  RescueSight
//
//  The "Drone feed" panel in the incident sheet.
//
//  Before launch: once fire is confirmed, a highlighted card invites the
//  responder to get eyes on the scene with a drone.
//  While live: the AI-annotated video, with live counts of people in view,
//  people who may be down (possible injury), people near the flames, and
//  how much of the view is on fire.
//  Snapshots the feed saved are listed underneath.
//
//  Without a drone connected, the server plays demo footage of a real fire
//  (public domain), clearly labeled as a demo.
//

import SwiftUI

struct DroneFeedSection: View {
    let summary: IncidentSummary
    let snapshots: [MediaItem]
    let onOpen: (MediaItem) -> Void

    @State private var viewModel: DroneFeedViewModel
    @State private var isFullScreen = false

    init(summary: IncidentSummary, snapshots: [MediaItem], onOpen: @escaping (MediaItem) -> Void) {
        self.summary = summary
        self.snapshots = snapshots
        self.onOpen = onOpen
        _viewModel = State(initialValue: DroneFeedViewModel(incidentID: summary.id))
    }

    var body: some View {
        SectionCard(title: "Drone feed", systemImage: "binoculars.fill") {
            if viewModel.isLive, let status = viewModel.status {
                livePanel(status)
            } else {
                launchPanel
            }
            if !snapshots.isEmpty {
                snapshotStrip
            }
        }
        .task { await viewModel.keepUpdating() }
        .fullScreenCover(isPresented: $isFullScreen) {
            LiveFeedFullScreen(viewModel: viewModel)
        }
        .alert("Drone feed problem", isPresented: Binding(
            get: { viewModel.actionError != nil },
            set: { if !$0 { viewModel.actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.actionError?.message ?? "")
        }
    }

    // MARK: - Before launch

    @ViewBuilder
    private var launchPanel: some View {
        let fireConfirmed = summary.ai.fireDetected
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: fireConfirmed ? "flame.fill" : "binoculars")
                    .font(.title2)
                    .foregroundStyle(fireConfirmed ? Color(.systemRed) : .secondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(fireConfirmed ? "Fire confirmed. Get eyes on the scene." : "Get a live view of the scene")
                        .font(.subheadline.weight(.semibold))
                    Text("The AI watches the drone's video for people, anyone who may be down or injured, people close to the flames, and how far the fire has spread.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let status = viewModel.status, status.hasRun {
                lastFeedSummary(status)
            }

            Button {
                Task { await viewModel.start() }
            } label: {
                HStack(spacing: Spacing.s) {
                    if viewModel.isChanging {
                        ProgressView().tint(fireConfirmed ? .white : nil)
                    } else {
                        Image(systemName: "dot.radiowaves.up.forward")
                    }
                    Text(viewModel.status?.hasRun == true ? "Launch again" : "Launch drone feed")
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(ProminenceButtonStyle(prominent: fireConfirmed))
            .tint(fireConfirmed ? Color(.systemRed) : .accentColor)
            .controlSize(.large)
            .disabled(viewModel.isChanging)
            .accessibilityIdentifier("launchDroneFeedButton")

            Text(viewModel.status?.cameraConnected == true
                 ? "Drone camera connected."
                 : "No drone connected yet, so this plays demo footage of a real fire (public domain). The AI results are real.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(fireConfirmed ? Spacing.m : 0)
        .background {
            if fireConfirmed {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color(.systemRed).opacity(0.08))
            }
        }
    }

    private func lastFeedSummary(_ status: LiveFeedStatus) -> some View {
        Label {
            Text("Last feed: up to \(status.peakPeople) \(status.peakPeople == 1 ? "person" : "people") in view"
                 + (status.peakPeopleDown > 0 ? ", \(status.peakPeopleDown) possibly down" : "")
                 + (status.fireSeen ? ", fire seen." : "."))
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    // MARK: - While live

    private func livePanel(_ status: LiveFeedStatus) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Button { isFullScreen = true } label: {
                LiveFrameView(image: viewModel.frame, status: status)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the feed full screen")

            if let now = status.now {
                LiveStatsGrid(stats: now)
            }

            Text("Most at once: \(status.peakPeople) \(status.peakPeople == 1 ? "person" : "people")"
                 + (status.peakPeopleNearFire > 0 ? " · \(status.peakPeopleNearFire) near the flames" : "")
                 + " · \(status.snapshotsSaved) \(status.snapshotsSaved == 1 ? "snapshot" : "snapshots") saved")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                Task { await viewModel.stop() }
            } label: {
                Label("Stop feed", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(viewModel.isChanging)
            .accessibilityIdentifier("stopDroneFeedButton")
        }
    }

    // MARK: - Snapshots

    private var snapshotStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Snapshots (\(snapshots.count))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    ForEach(snapshots.reversed()) { item in
                        Button { onOpen(item) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                RemoteImage(url: item.annotatedURL ?? item.thumbnailURL)
                                    .frame(width: 132, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                Text(item.analysis.shortSummary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 132, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Drone snapshot, \(item.analysis.shortSummary)")
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

/// The live picture with a red LIVE badge, the source, and how long it's been running.
struct LiveFrameView: View {
    let image: UIImage?
    let status: LiveFeedStatus

    var body: some View {
        Color.black
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Circle().fill(.white).frame(width: 7, height: 7)
                    Text("LIVE").font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemRed), in: Capsule())
                .padding(Spacing.s)
            }
            .overlay(alignment: .topTrailing) {
                Text(status.isDemo ? "Demo footage" : (status.sourceLabel ?? "Drone"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(Spacing.s)
            }
            .overlay(alignment: .bottomLeading) {
                if let started = status.startedAt {
                    Text(started, style: .timer)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(Spacing.s)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Live drone video with AI boxes")
            .accessibilityIdentifier("liveDroneFrame")
    }
}

/// Four big live numbers. Possible injuries and people near flames turn
/// red/amber when they're above zero, because those need attention first.
struct LiveStatsGrid: View {
    let stats: LiveStats

    private let columns = [GridItem(.flexible(), spacing: Spacing.s), GridItem(.flexible(), spacing: Spacing.s)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.s) {
            tile("People in view", value: "\(stats.peopleCount)", systemImage: "person.2.fill", alert: nil)
            tile("May be down", value: "\(stats.peopleDown)", systemImage: "figure.fall",
                 alert: stats.peopleDown > 0 ? Color(.systemRed) : nil)
            tile("Near the flames", value: "\(stats.peopleNearFire)", systemImage: "flame",
                 alert: stats.peopleNearFire > 0 ? Color(.systemOrange) : nil)
            tile("Fire in view", value: stats.fireDetected
                    ? stats.fireCoverage.formatted(.percent.precision(.fractionLength(0...1)))
                    : (stats.smokeDetected ? "Smoke" : "None"),
                 systemImage: "flame.fill", alert: stats.fireDetected ? Color(.systemRed) : nil)
        }
        .animation(.easeOut(duration: 0.2), value: stats)
    }

    private func tile(_ title: String, value: String, systemImage: String, alert: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(alert ?? .secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background((alert ?? Color.secondary).opacity(alert == nil ? 0.08 : 0.14),
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The feed filling the screen, with the live numbers below.
struct LiveFeedFullScreen: View {
    let viewModel: DroneFeedViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.l) {
                Spacer(minLength: 0)
                if let status = viewModel.status {
                    LiveFrameView(image: viewModel.frame, status: status)
                    if let now = status.now {
                        LiveStatsGrid(stats: now)
                    }
                    if !status.active {
                        Text("The feed has stopped.")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.l)
            .background(Color.black.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .navigationTitle("Drone feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
