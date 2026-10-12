//
//  LocationProvider.swift
//  RollCall
//
//  Gets the phone's current location once (for the household's pin) and turns
//  a location into a readable address like "1418 Lee St", "Greenville".
//
//  In the simulator, set a location with Features > Location > Custom
//  Location (or: xcrun simctl location booted set 33.07,-96.10).
//

import CoreLocation

final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    /// Callers waiting for a location answer.
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// True if the user said no to location access (or it's turned off).
    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// The current location, or nil if it's unavailable or not allowed.
    /// Asks for permission the first time.
    func currentLocation() async -> CLLocation? {
        if isDenied { return nil }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()  // shows the iPhone's permission prompt
            } else {
                manager.requestLocation()
            }
        }
    }

    /// A short name for a spot on the map, like "Main St, Greenville".
    func placeName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let place = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        let parts = [place.thoroughfare, place.locality].compactMap { $0 }
        return parts.isEmpty ? place.name : parts.joined(separator: ", ")
    }

    /// The street address and town for a spot, e.g. ("1418 Lee St", "Greenville").
    func address(for coordinate: CLLocationCoordinate2D) async -> (street: String, city: String)? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let place = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        let street = [place.subThoroughfare, place.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return (street.isEmpty ? (place.name ?? "") : street, place.locality ?? "")
    }

    private func finish(with location: CLLocation?) {
        let callers = waiting
        waiting.removeAll()
        callers.forEach { $0.resume(returning: location) }
    }

    // MARK: - CLLocationManagerDelegate
    // The location manager calls these on the main thread (where it was
    // created), so it's safe to touch our properties directly.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            // Use our own `self.manager` (it's the same object) to stay on the main actor.
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if !waiting.isEmpty { self.manager.requestLocation() }
            case .denied, .restricted:
                finish(with: nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { finish(with: locations.last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(with: nil) }
    }
}
