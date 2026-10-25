//
//  ResidentHomeViewModel.swift
//  RollCall
//
//  Loads the resident's own household and any volunteers asking to be their
//  buddy; answers those requests; and deletes everything ("Delete my data").
//

import Foundation
import Observation

@Observable
final class ResidentHomeViewModel {
    let householdID: Int
    private(set) var state: LoadState<Household> = .loading
    private(set) var buddyRequests: [BuddyRequestToMe] = []
    private(set) var isDeleting = false
    private(set) var isAnswering = false
    var actionError: APIError?

    private let api: APIClient

    init(householdID: Int, api: APIClient = .shared) {
        self.householdID = householdID
        self.api = api
    }

    var household: Household? { state.value }

    func load() async {
        do {
            async let household = api.fetchHousehold(id: householdID)
            async let requests = api.fetchBuddyRequestsToMe()
            state = .loaded(try await household)
            buddyRequests = (try? await requests) ?? []
        } catch {
            // (async let forgets that only APIErrors can be thrown, so convert back.)
            if household == nil { state = .failed(error as? APIError ?? .serverUnreachable) }
        }
    }

    func retry() async {
        state = .loading
        await load()
    }

    /// The profile was edited: show the saved version right away.
    func replace(with household: Household) {
        state = .loaded(household)
    }

    /// Accept or decline a volunteer who asked to check on this household.
    func answer(_ request: BuddyRequestToMe, accept: Bool) async {
        isAnswering = true
        defer { isAnswering = false }
        do {
            try await api.answerBuddyRequest(id: request.id, accept: accept)
            await load()
        } catch {
            actionError = error
        }
    }

    func removeBuddy() async {
        do {
            try await api.removeMyBuddy()
            await load()
        } catch {
            actionError = error
        }
    }

    /// Returns true once everything is deleted on the server.
    func deleteMyData() async -> Bool {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await api.deleteHousehold(id: householdID)
            return true
        } catch {
            actionError = error
            return false
        }
    }

    // MARK: - Check-in

    private(set) var isCheckingIn = false

    /// "I'm safe" or "I need help". Your buddy sees it right away.
    func checkIn(safe: Bool) async -> Bool {
        isCheckingIn = true
        defer { isCheckingIn = false }
        do {
            replace(with: try await api.checkIn(safe: safe))
            await AlertsManager.shared.didCheckIn(safe: safe, place: "")
            return true
        } catch {
            actionError = error
            return false
        }
    }
}
