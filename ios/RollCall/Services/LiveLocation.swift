//
//  LiveLocation.swift
//  RollCall
//
//  Follows the phone's location and which way it's pointing, for the blue
//  dot on the Map (like Google Maps). It only starts after the user taps
//  "Use my location", and the first time iOS asks for permission.
//
//  The heading (compass direction) only exists on a real iPhone. In the
//  simulator the dot shows without its direction cone.
//

import CoreLocation
import Observation

@Observable
final class LiveLocation: NSObject, CLLocationManagerDelegate {
    /// Where the phone is (nil until the first fix).
    private(set) var location: CLLocation?
    /// Which way the top of the phone points, in degrees from north (nil if unknown).
    private(set) var heading: CLLocationDirection?
    private(set) var authorization: CLAuthorizationStatus
    private(set) var isRunning = false

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5          // meters; skip tiny jitters
        manager.headingFilter = 3           // degrees
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }
    var isAllowed: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }

    /// Start following the phone. Shows the iPhone's permission popup the first time.
    func start() {
        isRunning = true
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()   // updates start once the user answers
        } else if isAllowed {
            beginUpdates()
        }
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    private func beginUpdates() {
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    // MARK: - CLLocationManagerDelegate
    // The manager calls these on the main thread (where it was created).

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorization = self.manager.authorizationStatus
            if isRunning && isAllowed { beginUpdates() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last?.copy() as? CLLocation
        MainActor.assumeIsolated { location = latest }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Copy the numbers out first, so only plain values cross to the main actor.
        let accuracy = newHeading.headingAccuracy
        let direction = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        MainActor.assumeIsolated {
            heading = accuracy >= 0 ? direction : nil   // negative accuracy = not reliable
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Short failures (no GPS fix yet) are normal. The last location stays.
    }
}
