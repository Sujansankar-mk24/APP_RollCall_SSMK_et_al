//
//  IncidentDetailView.swift
//  RescueSight
//
//  The bottom sheet that opens when you tap an incident. It can sit at half
//  height (map still visible) or be dragged up to full height.
//
//  Sections, top to bottom:
//    header (type, place, status, priority, quick facts)
//    AI analysis  ·  Drone feed  ·  Why this priority?  ·  Photos & videos  ·  Timeline
//    responder buttons pinned to the bottom
//

import SwiftUI

struct IncidentDetailView: View {
    @State private var viewModel: IncidentDetailViewModel
    @State private var openMedia: MediaItem?

    /// Tells the map to refresh after a responder changes the status.
    let onStatusChanged: () -> Void

    init(summary: IncidentSummary, onStatusChanged: @escaping () -> Void) {
        _viewModel = State(initialValue: IncidentDetailViewModel(summary: summary))
        self.onStatusChanged = onStatusChanged
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                DetailHeader(summary: viewModel.summary)
                sections
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            if viewModel.detail != nil {
                ResponderActionBar(summary: viewModel.summary, isWorking: viewModel.isUpdatingStatus) { status in
                    Task {
                        if await viewModel.setStatus(status) { onStatusChanged() }
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.summary.status)  // a little tap when the status changes
        .animation(.easeOut(duration: 0.2), value: viewModel.summary)
        .task {
            await viewModel.load()
            await viewModel.keepUpdating()
        }
        .refreshable { await viewModel.load() }
        .fullScreenCover(item: $openMedia) { item in
            MediaViewer(item: item)
        }
        .alert("Couldn't update the incident", isPresented: Binding(
            get: { viewModel.actionError != nil },
            set: { if !$0 { viewModel.actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.actionError?.message ?? "")
        }
    }

    @ViewBuilder
    private var sections: some View {
        switch viewModel.loadState {
        case .loading:
            loadingPlaceholder

        case .failed(let error):
            MessageCard(
                systemImage: "exclamationmark.icloud",
                title: "Couldn't load the details",
                message: error.message,
                actionTitle: "Try again",
                action: { Task { await viewModel.retry() } }
            )
            .frame(maxWidth: .infinity)

        case .loaded(let detail):
            AIAnalysisCard(detail: detail) { openMedia = $0 }
            DroneFeedSection(summary: detail.summary, snapshots: detail.cameraFeed) { openMedia = $0 }
            PriorityBreakdownCard(priority: detail.summary.priority)
            MediaGallerySection(media: detail.uploads) { openMedia = $0 }
            TimelineSection(events: detail.timeline)
        }
    }

    /// Gray shapes the size of the real cards, shown while the details load.
    private var loadingPlaceholder: some View {
        VStack(spacing: Spacing.xl) {
            ForEach([180.0, 140, 120], id: \.self) { height in
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(height: height)
            }
        }
        .overlay { ProgressView() }
        .accessibilityLabel("Loading incident details")
    }
}
