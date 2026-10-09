//
//  APIClient.swift
//  RescueSight
//
//  The only place in the app that talks to the backend. Views and view
//  models call these functions and get back Swift structs or an APIError.
//

import Foundation

struct APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL = AppConfig.apiBaseURL) {
        self.baseURL = baseURL

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConfig.requestTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData  // always get fresh data
        session = URLSession(configuration: configuration)

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase  // report_count -> reportCount
        decoder.dateDecodingStrategy = .iso8601              // "2026-10-09T04:10:44Z" -> Date
    }

    // MARK: - Endpoints

    /// All incidents, highest priority first. (Filtering happens in the app,
    /// so changing a filter is instant and doesn't need the network.)
    func fetchIncidents() async throws(APIError) -> [IncidentSummary] {
        try await send(URLRequest(url: baseURL.appending(path: "incidents")))
    }

    /// One incident with its reports, media, AI results and timeline.
    func fetchIncident(id: Int) async throws(APIError) -> IncidentDetail {
        try await send(URLRequest(url: baseURL.appending(path: "incidents/\(id)")))
    }

    /// A responder marks an incident responding / resolved (or active again).
    /// The server answers with the updated incident.
    func updateStatus(incidentID: Int, to status: IncidentStatus) async throws(APIError) -> IncidentDetail {
        var request = URLRequest(url: baseURL.appending(path: "incidents/\(incidentID)/status"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"status": "\#(status.rawValue)"}"#.utf8)
        return try await send(request)
    }

    // MARK: - Plumbing

    /// Send a request and decode the JSON answer into whatever type the caller expects.
    private func send<Response: Decodable>(_ request: URLRequest) async throws(APIError) -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .serverUnreachable
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw .badResponse(statusCode: http.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw .unreadableResponse
        }
    }
}
