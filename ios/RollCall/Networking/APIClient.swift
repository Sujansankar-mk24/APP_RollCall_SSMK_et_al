//
//  APIClient.swift
//  RollCall
//
//  The only place in the app that talks to the backend. Views and view
//  models call these functions and get back Swift structs or an APIError.
//
//  Every request carries the signed-in account's token. The SERVER decides
//  what that person may see, so privacy doesn't depend on the app hiding things.
//

import CoreLocation
import Foundation

struct APIClient {
    static let shared = APIClient()

    /// Fixed address (for previews/tests), or nil to follow the server setting.
    private let fixedBaseURL: URL?
    private var baseURL: URL { fixedBaseURL ?? AppConfig.apiBaseURL }
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL? = nil) {
        fixedBaseURL = baseURL

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConfig.requestTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData  // always get fresh data
        session = URLSession(configuration: configuration)

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase  // contact_name -> contactName
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase    // contactName -> contact_name
    }

    // MARK: - Incidents (Map and Incidents tabs)

    /// All incidents, highest priority first. (Filtering happens in the app,
    /// so changing a filter is instant and doesn't need the network.)
    func fetchIncidents() async throws(APIError) -> [IncidentSummary] {
        try await send(request("incidents"))
    }

    /// One incident with its reports, media, AI results and timeline.
    func fetchIncident(id: Int) async throws(APIError) -> IncidentDetail {
        try await send(request("incidents/\(id)"))
    }

    /// A responder marks an incident responding / resolved (or active again).
    /// The server answers with the updated incident.
    func updateStatus(incidentID: Int, to status: IncidentStatus) async throws(APIError) -> IncidentDetail {
        try await send(request("incidents/\(incidentID)/status", method: "PATCH", body: ["status": status.rawValue]))
    }

    /// Send a new report, with its photo or video if there is one. The server
    /// either adds it to a nearby matching incident or starts a new one.
    func submitReport(_ report: ReportSubmission) async throws(APIError) -> ReportCreated {
        var form = MultipartForm()
        form.addField("type", report.type.rawValue)
        form.addField("latitude", String(report.coordinate.latitude))
        form.addField("longitude", String(report.coordinate.longitude))
        form.addField("description", report.description)
        form.addField("location_name", report.locationName)

        switch report.attachment {
        case .photo(let jpeg, _):
            form.addFile("file", fileName: "photo.jpg", mimeType: "image/jpeg", data: jpeg)
        case .video(let file, _):
            guard let data = try? Data(contentsOf: file) else { throw .unreadableAttachment }
            let isMOV = file.pathExtension.lowercased() == "mov"
            form.addFile("file", fileName: isMOV ? "video.mov" : "video.mp4",
                         mimeType: isMOV ? "video/quicktime" : "video/mp4", data: data)
        case nil:
            break
        }

        var request = request("reports", method: "POST")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finished()
        request.timeoutInterval = 120  // videos can take a little while to upload
        return try await send(request)
    }

    // MARK: - Server

    /// Is there a RollCall server at this address? (Used before switching servers.)
    func isRollCallServer(at url: URL) async -> Bool {
        var request = URLRequest(url: url.appending(path: "health"))
        request.timeoutInterval = 8
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return String(data: data, encoding: .utf8)?.contains("ok") ?? false
    }

    // MARK: - Live hazards (Map tab)

    /// Real alerts, fires and storm reports, with their danger zones.
    func fetchHazards() async throws(APIError) -> HazardFeed {
        try await send(request("hazards"))
    }

    /// Start (or end) the demo Tornado Warning over Greenville.
    func setDemoWarning(on: Bool) async throws(APIError) {
        try await sendWithoutAnswer(request("demo/tornado-warning", method: on ? "POST" : "DELETE"))
    }

    // MARK: - Accounts

    func signUp(name: String, email: String, password: String) async throws(APIError) -> AuthResponse {
        try await send(request("auth/signup", method: "POST", body: ["name": name, "email": email, "password": password]))
    }

    func signIn(email: String, password: String) async throws(APIError) -> AuthResponse {
        try await send(request("auth/signin", method: "POST", body: ["email": email, "password": password]))
    }

    func signOut() async throws(APIError) {
        try await sendWithoutAnswer(request("auth/signout", method: "POST"))
    }

    func fetchMe() async throws(APIError) -> Me {
        try await send(request("me"))
    }

    func updateMe(rollCallOptOut: Bool) async throws(APIError) -> Me {
        try await send(request("me", method: "PATCH", body: ["roll_call_opt_out": rollCallOptOut]))
    }

    func becomeVolunteer(city: String) async throws(APIError) -> Me {
        try await send(request("me/volunteer", method: "PUT", body: ["city": city]))
    }

    func stopVolunteering() async throws(APIError) -> Me {
        try await send(request("me/volunteer", method: "DELETE"))
    }

    // MARK: - Demo accounts

    func fetchDemoAccounts() async throws(APIError) -> [DemoAccount] {
        try await send(request("demo/accounts"))
    }

    func signInDemo(userID: Int) async throws(APIError) -> AuthResponse {
        try await send(request("demo/signin", method: "POST", body: ["user_id": userID]))
    }

    // MARK: - Households (Roll Call tab)

    /// Join the roll call: create this account's household profile.
    func registerHousehold(_ input: HouseholdInput) async throws(APIError) -> Household {
        try await send(request("households", method: "POST", body: input))
    }

    func fetchHousehold(id: Int) async throws(APIError) -> Household {
        try await send(request("households/\(id)"))
    }

    func updateHousehold(id: Int, _ input: HouseholdInput) async throws(APIError) -> Household {
        try await send(request("households/\(id)", method: "PUT", body: input))
    }

    /// "Delete my data": removes the household and everything attached to it.
    func deleteHousehold(id: Int) async throws(APIError) {
        try await sendWithoutAnswer(request("households/\(id)", method: "DELETE"))
    }

    // MARK: - Buddies: the resident's side

    func fetchBuddyRequestsToMe() async throws(APIError) -> [BuddyRequestToMe] {
        try await send(request("me/buddy-requests"))
    }

    func answerBuddyRequest(id: Int, accept: Bool) async throws(APIError) {
        try await sendWithoutAnswer(request("me/buddy-requests/\(id)/\(accept ? "accept" : "decline")", method: "POST"))
    }

    func removeMyBuddy() async throws(APIError) {
        try await sendWithoutAnswer(request("me/buddy", method: "DELETE"))
    }

    // MARK: - Buddies: the volunteer's side

    func fetchBuddyResidents() async throws(APIError) -> [Household] {
        try await send(request("buddy/residents"))
    }

    func fetchNeighborsWantingBuddy() async throws(APIError) -> [NeighborWantingBuddy] {
        try await send(request("buddy/neighbors"))
    }

    func fetchSentBuddyRequests() async throws(APIError) -> [BuddyRequestSent] {
        try await send(request("buddy/requests"))
    }

    func askToCheckOn(neighbor: NeighborWantingBuddy) async throws(APIError) -> BuddyRequestSent {
        try await send(request("buddy/requests/community", method: "POST", body: ["household_id": neighbor.householdId]))
    }

    func askToCheckOn(address: AddressInput) async throws(APIError) -> BuddyRequestSent {
        try await send(request("buddy/requests/address", method: "POST", body: address))
    }

    func cancelBuddyRequest(id: Int) async throws(APIError) {
        try await sendWithoutAnswer(request("buddy/requests/\(id)", method: "DELETE"))
    }

    // MARK: - Communities

    func searchCommunities(_ text: String) async throws(APIError) -> [CommunitySummary] {
        var request = request("communities")
        request.url = request.url?.appending(queryItems: [URLQueryItem(name: "q", value: text)])
        return try await send(request)
    }

    func fetchCommunity(id: Int) async throws(APIError) -> CommunityDetail {
        try await send(request("communities/\(id)"))
    }

    func createCommunity(name: String, city: String) async throws(APIError) -> CommunityDetail {
        try await send(request("communities", method: "POST", body: ["name": name, "city": city]))
    }

    func joinCommunity(id: Int) async throws(APIError) {
        try await sendWithoutAnswer(request("communities/\(id)/join", method: "POST"))
    }

    func leaveCommunity(id: Int) async throws(APIError) {
        try await sendWithoutAnswer(request("communities/\(id)/leave", method: "POST"))
    }

    func answerJoinRequest(communityID: Int, userID: Int, approve: Bool) async throws(APIError) -> CommunityDetail {
        try await send(request("communities/\(communityID)/requests/\(userID)/\(approve ? "approve" : "decline")", method: "POST"))
    }

    func setOutsideBuddies(communityID: Int, allowed: Bool) async throws(APIError) -> CommunityDetail {
        try await send(request("communities/\(communityID)", method: "PATCH", body: ["allow_outside_buddies": allowed]))
    }

    // MARK: - Plumbing

    /// The signed-in account's token (kept in the Keychain by AuthStore).
    static var token: String?

    /// Posted when the server says the saved sign-in is no longer valid.
    static let signedOutNotification = Notification.Name("RollCallSignedOut")

    private func request(_ path: String, method: String = "GET", body: (some Encodable)? = Optional<Int>.none) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        if let token = Self.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body, let data = try? encoder.encode(body) {
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Send a request and decode the JSON answer into whatever type the caller expects.
    private func send<Response: Decodable>(_ request: URLRequest) async throws(APIError) -> Response {
        let data = try await perform(request)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw .unreadableResponse
        }
    }

    private func sendWithoutAnswer(_ request: URLRequest) async throws(APIError) {
        _ = try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws(APIError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .serverUnreachable
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // The server explains refusals in plain words ({"detail": "..."}); pass that on.
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            let isSignIn = request.url?.path().hasPrefix("/auth/sign") ?? false
            switch http.statusCode {
            case 401 where !isSignIn:
                NotificationCenter.default.post(name: Self.signedOutNotification, object: nil)
                throw .signedOut
            case 403: throw .notShared(detail ?? "")
            case 404: throw .notFound
            case 400, 401, 409: throw .refused(detail ?? "")
            case 422: throw .refused(String(localized: "Please check what you typed."))
            default: throw .badResponse(statusCode: http.statusCode)
            }
        }
        return data
    }
}
