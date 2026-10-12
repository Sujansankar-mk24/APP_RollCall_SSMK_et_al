//
//  ResidentHomeViewModel.swift
//  RollCall
//
//  Loads the resident's own household, and deletes it ("Delete my data").
//

import Foundation
import Observation

@Observable
final class ResidentHomeViewModel {
    let householdID: Int
    private(set) var state: LoadState<Household> = .loading
    private(set) var isDeleting = false
    var deleteError: APIError?

    private let api: APIClient
    private var viewer: Viewer { Viewer(role: .resident, id: householdID) }

    init(householdID: Int, api: APIClient = .shared) {
        self.householdID = householdID
        self.api = api
    }

    var household: Household? { state.value }

    func load() async {
        do {
            state = .loaded(try await api.fetchHousehold(id: householdID, as: viewer))
        } catch {
            if household == nil { state = .failed(error) }
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

    /// Returns true once everything is deleted on the server.
    func deleteMyData() async -> Bool {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await api.deleteHousehold(id: householdID, as: viewer)
            return true
        } catch {
            deleteError = error
            return false
        }
    }
}
