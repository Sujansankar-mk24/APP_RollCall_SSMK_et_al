//
//  CommunityViewModel.swift
//  RollCall
//
//  Everything on the Community tab: searching neighborhoods, asking to join,
//  creating one, the Weekly Recap, the first responders nearby, and (for
//  admins) approving people and photos.
//

import Foundation
import Observation

@Observable
final class CommunityViewModel {
    var query = ""
    private(set) var results: [CommunitySummary] = []
    private(set) var isSearching = false
    private(set) var detail: LoadState<CommunityDetail> = .loading
    private(set) var isWorking = false
    var actionError: APIError?

    private let api: APIClient
    private var searchTask: Task<Void, Never>?

    init(api: APIClient = .shared) { self.api = api }

    // MARK: - Finding a community

    /// Search as the person types (after a short pause).
    func queryChanged() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    func search() async {
        isSearching = true
        defer { isSearching = false }
        results = (try? await api.searchCommunities(query.trimmed)) ?? []
    }

    func join(_ community: CommunitySummary, auth: AuthStore) async {
        await run(auth) { () async throws(APIError) in try await self.api.joinCommunity(id: community.id) }
    }

    /// Returns true if it was created.
    func create(name: String, city: String, auth: AuthStore) async -> Bool {
        await run(auth) { () async throws(APIError) in _ = try await self.api.createCommunity(name: name.trimmed, city: city.trimmed) }
    }

    // MARK: - Your community

    func loadDetail(id: Int) async {
        do {
            detail = .loaded(try await api.fetchCommunity(id: id))
        } catch {
            if detail.value == nil { detail = .failed(error) }
        }
    }

    func leave(id: Int, auth: AuthStore) async {
        await run(auth) { () async throws(APIError) in try await self.api.leaveCommunity(id: id) }
        detail = .loading
    }

    func answer(_ person: CommunityMember, approve: Bool, in community: CommunityDetail) async {
        isWorking = true
        defer { isWorking = false }
        do {
            detail = .loaded(try await api.answerJoinRequest(communityID: community.id, userID: person.userId, approve: approve))
        } catch {
            actionError = error
        }
    }

    // MARK: - Community picture and Weekly Recap

    /// Set after a photo is sent for the recap, to show a confirmation.
    var photoSent = false

    func setPhoto(_ jpeg: Data, in community: CommunityDetail) async {
        await updateDetail { () async throws(APIError) in try await self.api.setCommunityPhoto(communityID: community.id, jpeg: jpeg) }
    }

    func addRecapPhoto(_ jpeg: Data, caption: String, in community: CommunityDetail) async {
        if await updateDetail({ () async throws(APIError) in
            try await self.api.addRecapPhoto(communityID: community.id, jpeg: jpeg, caption: caption.trimmed)
        }) {
            photoSent = true
        }
    }

    func change(_ photo: RecapPhoto, _ action: APIClient.RecapAction, in community: CommunityDetail) async {
        await updateDetail { () async throws(APIError) in
            try await self.api.changeRecapPhoto(communityID: community.id, photoID: photo.id, action)
        }
    }

    func remove(_ photo: RecapPhoto, in community: CommunityDetail) async {
        do throws(APIError) {
            try await api.deleteRecapPhoto(communityID: community.id, photoID: photo.id)
            await loadDetail(id: community.id)
        } catch {
            actionError = error
        }
    }

    @discardableResult
    private func updateDetail(_ work: () async throws(APIError) -> CommunityDetail) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            detail = .loaded(try await work())
            return true
        } catch {
            actionError = error
            return false
        }
    }

    // MARK: - First responders nearby

    private(set) var responders: [Person] = []

    /// Verified first responders in this town (or everywhere, if no town).
    func loadResponders(city: String?) async {
        responders = (try? await api.fetchResponders(city: city)) ?? []
    }

    @discardableResult
    private func run(_ auth: AuthStore, _ work: () async throws(APIError) -> Void) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
            await auth.refresh()   // the account's community changed
            return true
        } catch {
            actionError = error
            return false
        }
    }
}
