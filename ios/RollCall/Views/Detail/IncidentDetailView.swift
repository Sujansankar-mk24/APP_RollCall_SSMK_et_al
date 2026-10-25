//
//  IncidentDetailView.swift
//  RollCall
//
//  The bottom sheet that opens when you tap an incident. It can sit at half
//  height (map still visible) or be dragged up to full height.
//
//  Sections, top to bottom:
//    header (type, place, status, priority, quick facts)
//    AI analysis  ·  Why this priority?  ·  Photos & videos  ·  Timeline
//    responder buttons pinned to the bottom
//

import SwiftUI

struct IncidentDetailView: View {
    @State private var viewModel: IncidentDetailViewModel
    @State private var openMedia: MediaItem?
    @Environment(AuthStore.self) private var auth

    /// Tells the map to refresh after a responder changes the status.
    let onStatusChanged: () -> Void

    init(summary: IncidentSummary, onStatusChanged: @escaping () -> Void) {
        _viewModel = State(initialValue: IncidentDetailViewModel(summary: summary))
        self.onStatusChanged = onStatusChanged
    }

    /// A report the AI couldn't confirm: nobody sees it on the map until a
    /// verified first responder says it's real.
    @ViewBuilder
    private var reviewBar: some View {
        if auth.me?.isResponder == true && viewModel.summary.status != .resolved {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("Under review: the AI couldn't confirm this, so it isn't on the map.", systemImage: "eye.trianglebadge.exclamationmark")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: Spacing.m) {
                    Button {
                        Task { if await viewModel.review(real: false) { onStatusChanged() } }
                    } label: { Text("Not real").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("dismissReport")
                    Button {
                        Task { if await viewModel.review(real: true) { onStatusChanged() } }
                    } label: { Text("It's real, show it").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("confirmReport")
                }
                .controlSize(.large)
                .disabled(viewModel.isUpdatingStatus)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .background(Color(.systemBackground))
            .overlay(alignment: .top) { Divider() }
        } else {
            statusNote(viewModel.summary.status == .resolved
                       ? "A responder looked at this and found it isn't an emergency."
                       : "Under review. The AI couldn't find this in the photo, so nobody has been alerted yet. A first responder will check it.",
                       systemImage: "eye.trianglebadge.exclamationmark")
        }
    }

    /// Shown at the bottom instead of the responder buttons.
    private func statusNote(_ text: LocalizedStringKey, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .background(Color(.systemBackground))
            .overlay(alignment: .top) { Divider() }
            .accessibilityIdentifier("statusNote")
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
                if viewModel.summary.underReview {
                    reviewBar
                } else if viewModel.summary.type.isNatural {
                    statusNote("Nobody can stop a \(viewModel.summary.type.title.lowercased()). It ends when the weather passes, so there's nothing to resolve.",
                               systemImage: "cloud.bolt.fill")
                } else if auth.me?.isResponder == true {
                    // Only verified first responders can change an incident.
                    ResponderActionBar(summary: viewModel.summary, isWorking: viewModel.isUpdatingStatus) { status in
                        Task {
                            if await viewModel.setStatus(status) { onStatusChanged() }
                        }
                    }
                } else {
                    statusNote("Only verified first responders can mark this responding or resolved.",
                               systemImage: "checkmark.seal")
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
            MessageCard(error: error, action: { Task { await viewModel.retry() } })
            .frame(maxWidth: .infinity)

        case .loaded(let detail):
            AIAnalysisCard(detail: detail) { openMedia = $0 }
            PriorityBreakdownCard(priority: detail.summary.priority)
            MediaGallerySection(media: detail.media) { openMedia = $0 }
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
