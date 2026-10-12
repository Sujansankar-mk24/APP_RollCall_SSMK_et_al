//
//  BuddyHomeViewModel.swift
//  RollCall
//
//  A volunteer buddy's lists: the households that accepted them, community
//  neighbors who asked for a buddy, and the requests they've sent.
//

import Foundation
import Observation

@Observable
final class BuddyHomeViewModel {
    private(set) var state: LoadState<[Household]> = .loading
    private(set) var neighbors: [NeighborWantingBuddy] = []
    private(set) var sent: [BuddyRequestSent] = []
    private(set) var isWorking = false
    var actionError: APIError?

    private let api: APIClient

    init(api: APIClient = .shared) { self.api = api }

    func load() async {
        do {
            async let residents = api.fetchBuddyResidents()
            async let neighbors = api.fetchNeighborsWantingBuddy()
            async let sent = api.fetchSentBuddyRequests()
            state = .loaded(try await residents)
            self.neighbors = (try? await neighbors) ?? []
            self.sent = (try? await sent) ?? []
        } catch {
            // (async let forgets that only APIErrors can be thrown, so convert back.)
            if state.value == nil { state = .failed(error as? APIError ?? .serverUnreachable) }
        }
    }

    func retry() async {
        state = .loading
        await load()
    }

    /// Offer to check on a neighbor from the community list.
    func offer(to neighbor: NeighborWantingBuddy) async {
        await run { () async throws(APIError) in _ = try await self.api.askToCheckOn(neighbor: neighbor) }
    }

    /// Ask to check on someone by typing their address. Returns true if sent.
    func ask(address: AddressInput) async -> Bool {
        await run { () async throws(APIError) in _ = try await self.api.askToCheckOn(address: address) }
    }

    /// Cancel a request, or stop checking on someone.
    func cancel(requestID: Int) async {
        await run { () async throws(APIError) in try await self.api.cancelBuddyRequest(id: requestID) }
    }

    @discardableResult
    private func run(_ work: () async throws(APIError) -> Void) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
            await load()
            return true
        } catch {
            actionError = error
            return false
        }
    }
}
