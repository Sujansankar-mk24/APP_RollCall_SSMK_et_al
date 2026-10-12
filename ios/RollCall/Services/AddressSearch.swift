//
//  AddressSearch.swift
//  RollCall
//
//  Type-ahead address search for the report form, using Apple Maps search
//  (MKLocalSearchCompleter). As you type "Main St Green...", it suggests
//  matching places, preferring ones in North Texas. Picking a suggestion
//  looks up its exact coordinates so the pin can move there.
//

import MapKit
import Observation

@Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {

    /// One suggestion row, e.g. "123 Main St" / "Greenville, TX, United States".
    struct Suggestion: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion
    }

    /// A place the person picked: where it is and what to call it.
    struct Place {
        let coordinate: CLLocationCoordinate2D
        let name: String
    }

    var query = "" {
        didSet {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                suggestions = []
            } else {
                completer.queryFragment = query
            }
        }
    }
    private(set) var suggestions: [Suggestion] = []
    private(set) var isLookingUp = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = AppConfig.homeRegion  // prefer results near North Texas
    }

    /// Get the exact location of a suggestion.
    func place(for suggestion: Suggestion) async -> Place? {
        isLookingUp = true
        defer { isLookingUp = false }
        let name = suggestion.subtitle.isEmpty
            ? suggestion.title
            : "\(suggestion.title), \(suggestion.subtitle.components(separatedBy: ",").first ?? "")"

        // First choice: ask Apple Maps for the exact spot of this suggestion.
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion.completion))
        if let item = try? await search.start().mapItems.first {
            return Place(coordinate: item.placemark.coordinate, name: name)
        }
        // Backup: look the typed text up as an address instead.
        let text = "\(suggestion.title) \(suggestion.subtitle)"
        if let location = try? await CLGeocoder().geocodeAddressString(text).first?.location {
            return Place(coordinate: location.coordinate, name: name)
        }
        return nil
    }

    func clear() {
        query = ""
        suggestions = []
    }

    // MARK: - MKLocalSearchCompleterDelegate
    // The completer reports back on the main thread, so it's safe to update our
    // properties. We read from our own `completer` to stay on the main actor.

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            suggestions = self.completer.results.prefix(5).map {
                Suggestion(title: $0.title, subtitle: $0.subtitle, completion: $0)
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { suggestions = [] }
    }
}
