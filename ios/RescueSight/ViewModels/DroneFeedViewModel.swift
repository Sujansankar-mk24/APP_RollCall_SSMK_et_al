//
//  DroneFeedViewModel.swift
//  RescueSight
//
//  Runs the "Drone feed" panel. While the feed is live it asks the server
//  for the newest AI-annotated picture about 3 times a second and the live
//  numbers about once a second, which looks like video in the app.
//

import Foundation
import Observation
import UIKit

@Observable
final class DroneFeedViewModel {
    let incidentID: Int
    private(set) var status: LiveFeedStatus?
    private(set) var frame: UIImage?
    private(set) var isChanging = false   // starting or stopping
    var actionError: APIError?

    private let api: APIClient

    init(incidentID: Int, api: APIClient = .shared) {
        self.incidentID = incidentID
        self.api = api
    }

    var isLive: Bool { status?.active ?? false }

    /// Keep the panel up to date while it's on screen. SwiftUI cancels this
    /// loop when the sheet closes.
    func keepUpdating() async {
        var tick = 0
        while !Task.isCancelled {
            // Numbers: every 3rd tick (~1 s) while live, otherwise every ~4 s.
            if tick % 3 == 0 || !isLive {
                if let latest = try? await api.fetchLiveFeed(incidentID: incidentID) {
                    status = latest
                }
            }
            // Picture: every tick (~0.35 s) while live.
            if isLive, let path = status?.frameUrl,
               let data = try? await api.fetchLiveFrame(path: path),
               let image = UIImage(data: data) {
                frame = image
            }
            tick += 1
            try? await Task.sleep(for: isLive ? .milliseconds(350) : .seconds(4))
        }
    }

    func start() async {
        isChanging = true
        defer { isChanging = false }
        do {
            status = try await api.startLiveFeed(incidentID: incidentID)
        } catch {
            actionError = error
        }
    }

    func stop() async {
        isChanging = true
        defer { isChanging = false }
        do {
            status = try await api.stopLiveFeed(incidentID: incidentID)
            // The server needs a moment to finish; refresh shortly after.
            try? await Task.sleep(for: .milliseconds(800))
            status = try await api.fetchLiveFeed(incidentID: incidentID)
        } catch {
            actionError = error
        }
    }
}
