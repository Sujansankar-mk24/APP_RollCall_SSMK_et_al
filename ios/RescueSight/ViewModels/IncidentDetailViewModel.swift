//
//  IncidentDetailViewModel.swift
//  RescueSight
//
//  Loads one incident's full details for the detail sheet, and sends the
//  responder's "Mark responding" / "Mark resolved" actions to the server.
//

import Foundation
import Observation

@Observable
final class IncidentDetailViewModel {

    enum LoadState {
        case loading
        case loaded(IncidentDetail)
        case failed(APIError)
    }

    /// What the map already knows about this incident. Shown right away, so
    /// the top of the sheet appears instantly while the details download.
    private(set) var summary: IncidentSummary
    private(set) var loadState: LoadState = .loading
    private(set) var isUpdatingStatus = false
    /// Set when a status change fails, to show an alert.
    var actionError: APIError?

    private let api: APIClient

    init(summary: IncidentSummary, api: APIClient = .shared) {
        self.summary = summary
        self.api = api
    }

    var detail: IncidentDetail? {
        if case .loaded(let detail) = loadState { return detail }
        return nil
    }

    func load() async {
        do {
            let detail = try await api.fetchIncident(id: summary.id)
            summary = detail.summary
            loadState = .loaded(detail)
        } catch {
            // If we already have details, keep showing them instead of an error.
            if detail == nil { loadState = .failed(error) }
        }
    }

    func retry() async {
        loadState = .loading
        await load()
    }

    /// Returns true if the change was saved on the server.
    func setStatus(_ status: IncidentStatus) async -> Bool {
        isUpdatingStatus = true
        defer { isUpdatingStatus = false }
        do {
            let detail = try await api.updateStatus(incidentID: summary.id, to: status)
            summary = detail.summary
            loadState = .loaded(detail)
            return true
        } catch {
            actionError = error
            return false
        }
    }
}
