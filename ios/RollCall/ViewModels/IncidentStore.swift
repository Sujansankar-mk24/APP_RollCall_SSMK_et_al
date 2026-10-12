//
//  IncidentStore.swift
//  RollCall
//
//  The one shared copy of the incident list. The Map tab and the Incidents
//  tab both read from it, so a status change or a new report shows up in
//  both right away, and only one refresh loop runs.
//
//  It downloads incidents, keeps them fresh, and tracks whether we're
//  loading, loaded, or showing an error.
//

import Foundation
import Observation

@Observable
final class IncidentStore {

    enum LoadState: Equatable {
        case loading                 // first download in progress
        case loaded                  // we have data to show
        case failed(APIError)        // first download failed: nothing to show
    }

    /// Highest priority first; resolved incidents last (the server sorts them).
    private(set) var incidents: [IncidentSummary] = []
    private(set) var loadState: LoadState = .loading
    private(set) var lastUpdated: Date?
    /// A refresh failed AFTER we already had data. We keep showing the old
    /// data (better than a blank screen) with a warning that it may be stale.
    private(set) var refreshError: APIError?
    private(set) var isRefreshing = false

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Active, high-priority incidents: shown as the Incidents tab's badge.
    var needsAttentionCount: Int {
        incidents.filter(\.needsAttention).count
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

    /// The "Try again" button on an error screen.
    func retry() async {
        loadState = .loading
        await load()
    }

    /// Re-download every 30 seconds while a screen that uses it is visible, or
    /// every 2 seconds while the AI is still checking a photo/video (so results
    /// appear as soon as they're ready). SwiftUI cancels this loop
    /// automatically when the screen goes away.
    func keepRefreshing() async {
        while !Task.isCancelled {
            let isAnalyzing = incidents.contains { $0.ai.analyzing }
            try? await Task.sleep(for: isAnalyzing ? AppConfig.analysisPollInterval : AppConfig.refreshInterval)
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    /// After someone sends a photo/video: check every couple of seconds until
    /// the AI has finished with it, then return what it found (nil if it
    /// takes longer than a minute or the server can't be reached).
    func waitForAnalysis(incidentID: Int, mediaID: Int) async -> MediaAnalysis? {
        let deadline = Date.now.addingTimeInterval(60)
        while !Task.isCancelled, Date.now < deadline {
            if let detail = try? await api.fetchIncident(id: incidentID),
               let media = detail.media.first(where: { $0.id == mediaID }),
               !media.analysis.status.isInProgress {
                await load()  // update every screen with the new evidence and priority
                return media.analysis
            }
            try? await Task.sleep(for: AppConfig.analysisPollInterval)
        }
        return nil
    }
}
