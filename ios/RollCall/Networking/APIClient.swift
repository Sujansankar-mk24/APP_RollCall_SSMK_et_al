//
//  APIClient.swift
//  RollCall
//
//  The only place in the app that talks to the backend. Views and view
//  models call these functions and get back Swift structs or an APIError.
//
//  Roll Call requests also say who the app is acting as (X-Demo-Role / X-Demo-Id
//  headers). The SERVER decides what that person may see, so privacy doesn't
//  depend on the app hiding things.
//

import CoreLocation
import Foundation

struct APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = AppConfig.apiBaseURL) {
        self.baseURL = baseURL

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

    // MARK: - Households (Roll Call tab)

    /// Opt in: create a household profile. The answer includes its new id.
    func registerHousehold(_ input: HouseholdInput) async throws(APIError) -> Household {
        try await send(request("households", method: "POST", body: input))
    }

    func fetchHousehold(id: Int, as viewer: Viewer) async throws(APIError) -> Household {
        try await send(request("households/\(id)", viewer: viewer))
    }

    func updateHousehold(id: Int, _ input: HouseholdInput, as viewer: Viewer) async throws(APIError) -> Household {
        try await send(request("households/\(id)", method: "PUT", body: input, viewer: viewer))
    }

    /// "Delete my data": removes the household and everything attached to it.
    func deleteHousehold(id: Int, as viewer: Viewer) async throws(APIError) {
        try await sendWithoutAnswer(request("households/\(id)", method: "DELETE", viewer: viewer))
    }

    // MARK: - Volunteer buddies

    func fetchBuddyResidents(volunteerID: Int, as viewer: Viewer) async throws(APIError) -> [Household] {
        try await send(request("volunteers/\(volunteerID)/households", viewer: viewer))
    }

    // MARK: - Demo

    func fetchDemoIdentities() async throws(APIError) -> DemoIdentities {
        try await send(request("demo/identities"))
    }

    // MARK: - Plumbing

    private func request(_ path: String, method: String = "GET", body: (some Encodable)? = Optional<Int>.none,
                         viewer: Viewer? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        if let viewer {
            request.setValue(viewer.role.rawValue, forHTTPHeaderField: "X-Demo-Role")
            if let id = viewer.id { request.setValue(String(id), forHTTPHeaderField: "X-Demo-Id") }
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
            if http.statusCode == 403 { throw .notShared(detail ?? "") }
            if http.statusCode == 404 { throw .notFound }
            throw .badResponse(statusCode: http.statusCode)
        }
        return data
    }
}
