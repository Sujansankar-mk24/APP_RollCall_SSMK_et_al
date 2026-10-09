//
//  IncidentsView.swift
//  RescueSight
//
//  The responder view: key numbers at the top, then every incident sorted by
//  priority (highest first). Tap one to open the same detail sheet as on the map.
//

import SwiftUI

struct IncidentsView: View {
    @State private var viewModel: IncidentsViewModel
    @State private var selected: IncidentSummary?

    init(store: IncidentStore) {
        _viewModel = State(initialValue: IncidentsViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Incidents")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { AppearanceToolbarMenu() }
                }
        }
        .task {
            // Runs when the tab appears; SwiftUI cancels it when you leave.
            await viewModel.load()
            await viewModel.keepRefreshing()
        }
        .sheet(item: $selected) { incident in
            IncidentDetailView(summary: incident) {
                Task { await viewModel.load() }  // refresh the list after a status change
            }
            .id(incident.id)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Radius.panel)
        }
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            skeleton
        case .failed(let error):
            MessageCard(
                systemImage: "antenna.radiowaves.left.and.right.slash",
                title: error.title,
                message: error.message,
                actionTitle: "Try again",
                isWorking: viewModel.isRefreshing,
                action: { Task { await viewModel.retry() } }
            )
            .padding(Spacing.l)
            .frame(maxHeight: .infinity)
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                statusLine
                KPICards(kpis: viewModel.kpis)
                    .animation(.easeOut(duration: 0.25), value: viewModel.kpis)

                Picker("Show", selection: $viewModel.scope) {
                    ForEach(IncidentsViewModel.Scope.allCases) { scope in
                        Text("\(scope.title) (\(viewModel.count(for: scope)))").tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.visibleIncidents.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: Spacing.m) {
                        ForEach(viewModel.visibleIncidents) { incident in
                            Button { selected = incident } label: {
                                IncidentRow(incident: incident)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: viewModel.visibleIncidents.map(\.id))
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .refreshable { await viewModel.load() }   // pull down to refresh
    }

    /// "Updated 12 sec ago", or a warning if the last refresh failed.
    private var statusLine: some View {
        HStack(spacing: 6) {
            if viewModel.refreshError != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(.systemOrange))
                Text("Offline. Showing the last update")
            } else if viewModel.isRefreshing {
                ProgressView().controlSize(.mini)
                Text("Updating…")
            } else {
                Image(systemName: "clock").foregroundStyle(.secondary)
                if let updated = viewModel.lastUpdated {
                    Text("Updated \(Text(updated, style: .relative)) ago").monospacedDigit()
                }
            }
            Spacer()
            if viewModel.refreshError != nil {
                Button("Retry") { Task { await viewModel.load() } }
                    .frame(minHeight: minimumTapSize)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch viewModel.scope {
        case .open:
            MessageCard(systemImage: "checkmark.shield", title: "No open incidents",
                        message: "Every incident that was reported has been resolved.")
        case .resolved:
            MessageCard(systemImage: "tray", title: "Nothing resolved yet",
                        message: "Incidents appear here after a responder marks them resolved.")
        case .all:
            MessageCard(systemImage: "checkmark.shield", title: "No incidents reported",
                        message: "When people in your community report an emergency, it will appear here.")
        }
    }

    /// Gray shapes the size of the real content while the first download runs.
    private var skeleton: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.m) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .frame(height: 104)
                    }
                }
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(height: 116)
                }
            }
            .padding(Spacing.l)
        }
        .overlay { ProgressView() }
        .accessibilityLabel("Loading incidents")
    }
}
