//
//  APIClient.swift
//  RescueSight
//
//  The only place in the app that talks to the backend. Views and view
//  models call these functions and get back Swift structs or an APIError.
//

import CoreLocation
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

        var request = URLRequest(url: baseURL.appending(path: "reports"))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finished()
        request.timeoutInterval = 120  // videos can take a little while to upload
        return try await send(request)
    }

    // MARK: - Drone / camera feed

    func fetchLiveFeed(incidentID: Int) async throws(APIError) -> LiveFeedStatus {
        try await send(URLRequest(url: baseURL.appending(path: "incidents/\(incidentID)/camera")))
    }

    /// Launch the feed: the real drone camera if one is connected, otherwise demo footage.
    func startLiveFeed(incidentID: Int) async throws(APIError) -> LiveFeedStatus {
        var request = URLRequest(url: baseURL.appending(path: "incidents/\(incidentID)/camera/start"))
        request.httpMethod = "POST"
        return try await send(request)
    }

    func stopLiveFeed(incidentID: Int) async throws(APIError) -> LiveFeedStatus {
        var request = URLRequest(url: baseURL.appending(path: "incidents/\(incidentID)/camera/stop"))
        request.httpMethod = "POST"
        return try await send(request)
    }

    /// The newest picture from the feed (with AI boxes drawn on), as JPEG data.
    func fetchLiveFrame(path: String) async throws(APIError) -> Data {
        guard let url = AppConfig.mediaURL(path) else { throw .unreadableResponse }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.unreadableResponse }
            return data
        } catch {
            throw .serverUnreachable
        }
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
