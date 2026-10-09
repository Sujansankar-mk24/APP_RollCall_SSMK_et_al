//
//  MapViewModel.swift
//  RescueSight
//
//  The "brain" behind the map screen (the VM in MVVM). The incident data
//  itself lives in the shared IncidentStore; this adds what is specific to
//  the map: the filter chips and which incidents pass them.
//
//  @Observable means SwiftUI automatically redraws the map whenever one of
//  these properties changes.
//

import Foundation
import Observation

@Observable
final class MapViewModel {
    let store: IncidentStore
    var filters = MapFilters()

    init(store: IncidentStore) {
        self.store = store
    }

    // The shared data, passed through so the map view reads it from one place.
    var incidents: [IncidentSummary] { store.incidents }
    var loadState: IncidentStore.LoadState { store.loadState }
    var lastUpdated: Date? { store.lastUpdated }
    var refreshError: APIError? { store.refreshError }
    var isRefreshing: Bool { store.isRefreshing }

    /// The incidents that pass the current filters.
    var visibleIncidents: [IncidentSummary] {
        store.incidents.filter { filters.matches($0) }
    }

    func load() async { await store.load() }
    func retry() async { await store.retry() }
    func keepRefreshing() async { await store.keepRefreshing() }

    func waitForAnalysis(incidentID: Int, mediaID: Int) async -> MediaAnalysis? {
        await store.waitForAnalysis(incidentID: incidentID, mediaID: mediaID)
    }

    func clearFilters() {
        filters = MapFilters()
    }
}
