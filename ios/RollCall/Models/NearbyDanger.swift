//
//  NearbyDanger.swift
//  RollCall
//
//  "You're 2.1 miles from an active fire": finds the closest hazard to the
//  user, so the Map can warn them. Injuries aren't included (they're not a
//  danger to people nearby), and neither are resolved incidents.
//
//  Being inside an official alert's area counts as 0 miles away.
//

import CoreLocation

struct NearbyDanger: Equatable {
    enum Source: Equatable { case hazard(Hazard), incident(IncidentSummary) }

    let source: Source
    let title: String
    let kind: HazardKind
    let meters: Double
    let isInside: Bool

    var id: String {
        switch source {
        case .hazard(let hazard): "hazard-\(hazard.id)"
        case .incident(let incident): "incident-\(incident.id)"
        }
    }

    /// "0.4 mi" or "12 mi".
    var distanceText: String {
        let miles = meters / 1609.34
        return miles < 10 ? String(format: "%.1f mi", miles) : String(format: "%.0f mi", miles)
    }

    /// How close counts as "near" for each kind of hazard. Storms and floods
    /// cover more ground than a single fire.
    static func warningRadius(for kind: HazardKind) -> Double {
        switch kind {
        case .fire, .smoke: 8_000            // about 5 miles
        case .tornado, .hurricane: 25_000    // about 15 miles
        default: 15_000                      // about 9 miles
        }
    }

    /// The closest danger within its warning distance, if any.
    static func closest(to location: CLLocation, hazards: [Hazard],
                        incidents: [IncidentSummary]) -> NearbyDanger? {
        var found: [NearbyDanger] = []
        for hazard in hazards where hazard.kind != .injury {
            let inside = hazard.zones.contains { $0.outline.count > 2 && contains(location.coordinate, in: $0.outline) }
            let meters = inside ? 0 : location.distance(from: CLLocation(latitude: hazard.latitude, longitude: hazard.longitude))
            if meters <= warningRadius(for: hazard.kind) {
                found.append(NearbyDanger(source: .hazard(hazard), title: hazard.title, kind: hazard.kind,
                                          meters: meters, isInside: inside))
            }
        }
        for incident in incidents where incident.type != .injury && incident.status != .resolved && !incident.underReview {
            let kind = incident.type.hazardKind
            let meters = location.distance(from: CLLocation(latitude: incident.latitude, longitude: incident.longitude))
            if meters <= warningRadius(for: kind) {
                found.append(NearbyDanger(source: .incident(incident), title: "\(incident.type.title) reported",
                                          kind: kind, meters: meters, isInside: false))
            }
        }
        return found.min { $0.meters < $1.meters }
    }

    /// Is a point inside an outlined area? (Ray casting: count how many edges
    /// a line going east from the point crosses. Odd means inside.)
    static func contains(_ point: CLLocationCoordinate2D, in polygon: [CLLocationCoordinate2D]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude),
               point.longitude < (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
