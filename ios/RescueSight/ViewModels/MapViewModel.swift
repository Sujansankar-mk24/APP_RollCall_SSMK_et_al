//
//  MapViewModel.swift
//  RescueSight
//
//  The "brain" behind the map screen (the VM in MVVM). It downloads
//  incidents, keeps them fresh, applies the filters, and tracks whether
//  we're loading, loaded, or showing an error. The view just draws whatever
//  this object says.
//
//  @Observable means SwiftUI automatically redraws the map whenever one of
//  these properties changes.
//

import Foundation
import Observation

@Observable
final class MapViewModel {

    enum LoadState: Equatable {
        case loading                 // first download in progress
        case loaded                  // we have data to show
        case failed(APIError)        // first download failed: nothing to show
    }

    private(set) var incidents: [IncidentSummary] = []
    private(set) var loadState: LoadState = .loading
    private(set) var lastUpdated: Date?
    /// A refresh failed AFTER we already had data. We keep showing the old
    /// data (better than a blank map) with a warning that it may be stale.
    private(set) var refreshError: APIError?
    private(set) var isRefreshing = false

    var filters = MapFilters()

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// The incidents that pass the current filters.
    var visibleIncidents: [IncidentSummary] {
        incidents.filter { filters.matches($0) }
    }

    /// Download the latest incidents.
    func load() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            incidents = try await api.fetchIncidents()
            lastUpdated = .now
            refreshError = nil
            loadState = .loaded
        } catch {
            if incidents.isEmpty {
                loadState = .failed(error)   // nothing to show: full error screen
            } else {
                refreshError = error         // keep old data, show a small warning
            }
        }
    }

    /// The "Try again" button on the error screen.
    func retry() async {
        loadState = .loading
        await load()
    }

    /// Re-download every 30 seconds while the map is on screen. SwiftUI
    /// cancels this loop automatically when the screen goes away.
    func keepRefreshing() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: AppConfig.refreshInterval)
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    func clearFilters() {
        filters = MapFilters()
    }
}
