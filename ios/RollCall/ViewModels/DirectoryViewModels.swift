//
//  DirectoryViewModels.swift
//  RollCall
//
//  Two simple lists:
//    * the demo people you can act as (role switcher), and
//    * the residents a volunteer buddy checks on.
//

import Foundation
import Observation

@Observable
final class DemoIdentitiesViewModel {
    private(set) var state: LoadState<DemoIdentities> = .loading
    private let api: APIClient

    init(api: APIClient = .shared) { self.api = api }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await api.fetchDemoIdentities())
        } catch {
            state = .failed(error)
        }
    }
}

@Observable
final class BuddyHomeViewModel {
    let volunteerID: Int
    private(set) var state: LoadState<[Household]> = .loading
    private let api: APIClient

    init(volunteerID: Int, api: APIClient = .shared) {
        self.volunteerID = volunteerID
        self.api = api
    }

    func load() async {
        do {
            state = .loaded(try await api.fetchBuddyResidents(volunteerID: volunteerID,
                                                              as: Viewer(role: .buddy, id: volunteerID)))
        } catch {
            if state.value == nil { state = .failed(error) }
        }
    }

    func retry() async {
        state = .loading
        await load()
    }
}
