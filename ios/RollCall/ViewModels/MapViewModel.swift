//
//  MapViewModel.swift
//  RollCall
//
//  The "brain" behind the map screen (the VM in MVVM). The incident data
//  itself lives in the shared IncidentStore; this adds what is specific to
//  the map: live hazards (real alerts and fires), the filter chips, and
//  what passes them.
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

    /// Live hazards from the National Weather Service, NASA and NOAA.
    private(set) var hazardFeed: HazardFeed?
    private(set) var hazardError: APIError?
    private(set) var isChangingDemo = false

    private let api: APIClient

    init(store: IncidentStore, api: APIClient = .shared) {
        self.store = store
        self.api = api
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

    /// Live hazards that pass the filters, least serious first (so the most
    /// serious are drawn on top).
    var visibleHazards: [Hazard] {
        (hazardFeed?.hazards ?? []).filter { filters.matches($0) }.sorted { $0.level.rank < $1.level.rank }
    }

    var isDemoWarningOn: Bool { hazardFeed?.hazards.contains { $0.isDemo } ?? false }

    func load() async {
        async let incidents: () = store.load()
        async let hazards: () = loadHazards()
        _ = await (incidents, hazards)
    }

    func retry() async { await store.retry() }

    /// Refresh incidents and live hazards every so often while the map is on screen.
    func keepRefreshing() async {
        async let incidents: () = store.keepRefreshing()
        while !Task.isCancelled {
            try? await Task.sleep(for: AppConfig.refreshInterval)
            guard !Task.isCancelled else { break }
            await loadHazards()
        }
        await incidents
    }

    /// The refresh button: new incidents, and live data straight from the sources.
    private(set) var isRefreshingAll = false
    func refreshEverything() async {
        isRefreshingAll = true
        defer { isRefreshingAll = false }
        async let incidents: () = store.load()
        async let hazards: () = loadHazards(fresh: true)
        _ = await (incidents, hazards)
    }

    func loadHazards(fresh: Bool = false) async {
        do {
            hazardFeed = try await api.fetchHazards(fresh: fresh)
            hazardError = nil
        } catch {
            hazardError = error   // keep showing the last good data
        }
    }

    /// Start or end the demo Tornado Warning (labeled "Demo" everywhere).
    func setDemoWarning(on: Bool) async {
        isChangingDemo = true
        defer { isChangingDemo = false }
        try? await api.setDemoWarning(on: on)
        await loadHazards()
    }

    func waitForAnalysis(incidentID: Int, mediaID: Int) async -> MediaAnalysis? {
        await store.waitForAnalysis(incidentID: incidentID, mediaID: mediaID)
    }

    func clearFilters() {
        filters = MapFilters()
    }
}
