//
//  IncidentsPanel.swift
//  RollCall
//
//  The incident log, opened from the "Incidents" button at the top left of
//  the Map. It unrolls over the top-left of the screen (the map stays usable
//  around it) and keeps the incident-log look: key numbers, Open / Resolved /
//  All, and every incident sorted by priority, one ruled line each.
//
//  Tapping an incident folds the panel up and shows that incident on the map.
//
//  The open/close motion follows the "Accordion" transition from
//  transitions.dev: the panel grows and shrinks in 250 ms on the curve
//  cubic-bezier(0.22, 1, 0.36, 1), its contents fade in from a slight blur,
//  and the chevron flips from "v" to "^". Reduce Motion turns it off.
//

import SwiftUI

/// The recipe's motion.
enum Accordion {
    static var motion: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: 0.25) }

    /// Unroll from the top: a mask grows downward while the contents fade in
    /// from a slight blur (the panel itself keeps its full size, so its list
    /// always starts at the top).
    static var reveal: AnyTransition {
        .modifier(active: Reveal(progress: 0), identity: Reveal(progress: 1))
    }

    struct Reveal: ViewModifier, Animatable {
        var progress: CGFloat
        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            content
                .opacity(progress)
                .blur(radius: (1 - progress) * 2)
                .mask(alignment: .top) {
                    Rectangle().scaleEffect(x: 1, y: max(progress, 0.001), anchor: .top)
                }
        }
    }
}

/// The button at the top left of the Map: "Incidents ⌄", with a red count of
/// urgent incidents.
struct IncidentsButton: View {
    let isOpen: Bool
    let urgentCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.fill")
                Text("Incidents")
                    .lineLimit(1)
                    .fixedSize()   // never squeezed onto two lines by the chips beside it
                if urgentCount > 0 {
                    Text("\(urgentCount)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color(.systemRed), in: Capsule())
                }
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    // Flip "v" to "^" (it passes through a flat line halfway).
                    .scaleEffect(x: 1, y: isOpen ? -1 : 1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: minimumTapSize)
            .floatingSurface(cornerRadius: minimumTapSize / 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(urgentCount > 0 ? "Incidents, \(urgentCount) urgent" : "Incidents")
        .accessibilityValue(isOpen ? "Open" : "Closed")
        .accessibilityHint(isOpen ? "Closes the incident list" : "Shows every incident, highest priority first")
        .accessibilityIdentifier("incidentsButton")
    }
}

struct IncidentsPanel: View {
    let onSelect: (IncidentSummary) -> Void
    let onClose: () -> Void
    @State private var viewModel: IncidentsViewModel

    init(store: IncidentStore, onSelect: @escaping (IncidentSummary) -> Void, onClose: @escaping () -> Void) {
        _viewModel = State(initialValue: IncidentsViewModel(store: store))
        self.onSelect = onSelect
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.ink).frame(height: 3)
            content
        }
        .background(Color.paper)
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1.5))
        .sheetBrand()
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text("By priority").sheetLabelStyle().foregroundStyle(.secondary)
                Text("Incidents").font(.sheetDisplay)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .frame(width: minimumTapSize, height: minimumTapSize)
                    .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close incidents")
            .accessibilityIdentifier("closeIncidents")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView("Loading incidents…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ScrollView {
                SheetMessage(error: error, action: { Task { await viewModel.retry() } })
                    .padding(Spacing.l)
            }
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

                SheetTabs(selection: $viewModel.scope, options: IncidentsViewModel.Scope.allCases.map {
                    (value: $0, title: "\($0.title) (\(viewModel.count(for: $0)))")
                })

                if viewModel.visibleIncidents.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.visibleIncidents) { incident in
                            Button { onSelect(incident) } label: {
                                IncidentRow(incident: incident)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: viewModel.visibleIncidents.map(\.id))
                }
            }
            .padding(Spacing.l)
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
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch viewModel.scope {
        case .open:
            SheetMessage("No open incidents", message: "Every incident that was reported has been resolved.",
                         systemImage: "checkmark.shield")
        case .resolved:
            SheetMessage("Nothing resolved yet", message: "Incidents appear here after a responder marks them resolved.",
                         systemImage: "tray")
        case .all:
            SheetMessage("No incidents reported", message: "When people in your community report an emergency, it will appear here.",
                         systemImage: "checkmark.shield")
        }
    }
}
