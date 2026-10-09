//
//  IncidentsViewModel.swift
//  RescueSight
//
//  The brain behind the Incidents tab (the responder view): the list shown
//  depends on which scope is picked (Open / Resolved / All), and the KPI
//  cards are worked out from the shared incident list.
//

import Foundation
import Observation

@Observable
final class IncidentsViewModel {
    let store: IncidentStore

    enum Scope: String, CaseIterable, Identifiable {
        case open, resolved, all
        var id: Self { self }

        var title: String {
            switch self {
            case .open: "Open"
            case .resolved: "Resolved"
            case .all: "All"
            }
        }

        func includes(_ status: IncidentStatus) -> Bool {
            switch self {
            case .open: status != .resolved
            case .resolved: status == .resolved
            case .all: true
            }
        }
    }

    var scope: Scope = .open

    init(store: IncidentStore) {
        self.store = store
    }

    var incidents: [IncidentSummary] { store.incidents }
    var loadState: IncidentStore.LoadState { store.loadState }
    var lastUpdated: Date? { store.lastUpdated }
    var refreshError: APIError? { store.refreshError }
    var isRefreshing: Bool { store.isRefreshing }

    /// The server already sorted these by priority (open first, highest score
    /// first, ties go to the newest report), so just filter and keep the order.
    var visibleIncidents: [IncidentSummary] {
        store.incidents.filter { scope.includes($0.status) }
    }

    var kpis: IncidentKPIs { IncidentKPIs(store.incidents) }

    func count(for scope: Scope) -> Int {
        store.incidents.filter { scope.includes($0.status) }.count
    }

    func load() async { await store.load() }
    func retry() async { await store.retry() }
    func keepRefreshing() async { await store.keepRefreshing() }
}
