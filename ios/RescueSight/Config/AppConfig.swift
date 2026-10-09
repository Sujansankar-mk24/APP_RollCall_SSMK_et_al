//
//  AppConfig.swift
//  RescueSight
//
//  Every setting you might want to change lives here, in one place.
//

import Foundation
import MapKit

enum AppConfig {

    /// Where the Python backend is running. The iPhone simulator shares the
    /// Mac's network, so "localhost" here means "this Mac".
    static let apiBaseURL = URL(string: "http://localhost:8000")!

    /// How long to wait for the server before showing an error.
    static let requestTimeout: TimeInterval = 10

    /// How often the map quietly re-downloads incidents.
    static let refreshInterval: Duration = .seconds(30)

    /// The area the map opens on (and returns to with the recenter button):
    /// North Texas, from McKinney and Sherman east to Paris and Sulphur Springs.
    static let homeRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 33.22, longitude: -96.10),
        span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 1.35)
    )

    /// Turns a path from the server like "/media/thumbs/3.jpg" into a full URL.
    static func mediaURL(_ path: String?) -> URL? {
        guard let path else { return nil }
        return URL(string: path, relativeTo: apiBaseURL)?.absoluteURL
    }
}
