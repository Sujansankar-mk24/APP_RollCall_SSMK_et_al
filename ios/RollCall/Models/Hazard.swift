//
//  Hazard.swift
//  RollCall
//
//  Live hazards (real alerts, fires and storm reports) and their danger
//  zones. Matches backend/app/hazards/models.py.
//
//  Two ideas the map uses everywhere:
//    * The COLOR says what kind of hazard it is (fire red-orange, tornado
//      purple, flood blue, ...). Community reports use the same colors.
//    * How SOLID a zone is says how dangerous it is: Immediate danger is the
//      strongest, Evacuate lighter, Be cautious a faint area with a dashed edge.
//

import CoreLocation
import SwiftUI

// MARK: - Zone levels

enum ZoneLevel: String, Codable, CaseIterable, Identifiable {
    case immediate, evacuate, cautious

    var id: Self { self }

    var title: String {
        switch self {
        case .immediate: "Immediate danger"
        case .evacuate: "Evacuate"
        case .cautious: "Be cautious"
        }
    }

    /// What someone inside this zone should do.
    var advice: String {
        switch self {
        case .immediate: "Get away or take shelter now."
        case .evacuate: "Leave the area, or be ready to shelter."
        case .cautious: "Stay alert, avoid the area, and be ready to act."
        }
    }

    /// How see-through the zone's fill is (streets stay readable underneath).
    var fillOpacity: Double {
        switch self {
        case .immediate: 0.34
        case .evacuate: 0.2
        case .cautious: 0.08
        }
    }

    var edge: StrokeStyle {
        switch self {
        case .immediate: StrokeStyle(lineWidth: 2)
        case .evacuate: StrokeStyle(lineWidth: 1.5)
        case .cautious: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
        }
    }

    /// Bigger = more serious.
    var rank: Int {
        switch self {
        case .immediate: 3
        case .evacuate: 2
        case .cautious: 1
        }
    }
}

// MARK: - Kinds of hazard

enum HazardKind: String, Codable, CaseIterable {
    case fire, smoke, tornado
    case severeStorm = "severe_storm"
    case heavyRain = "heavy_rain"
    case flood, hurricane
    case winterStorm = "winter_storm"
    case heat
    case airQuality = "air_quality"
    case earthquake, landslide, volcano, drought
    case injury, other

    /// A kind the app doesn't know yet (the server added one) shows as "other"
    /// instead of breaking the whole map.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HazardKind(rawValue: raw) ?? .other
    }

    /// A color that fits the hazard: fire is red-orange, a tornado purple,
    /// water blue, ice cyan. (Red alone isn't used for everything.)
    var color: Color {
        switch self {
        case .fire: Color(red: 0.93, green: 0.30, blue: 0.12)
        case .smoke: Color(red: 0.47, green: 0.47, blue: 0.50)
        case .tornado: Color(red: 0.56, green: 0.27, blue: 0.88)
        case .severeStorm: Color(red: 0.95, green: 0.64, blue: 0.08)
        case .heavyRain: Color(red: 0.10, green: 0.62, blue: 0.75)
        case .flood: Color(red: 0.11, green: 0.42, blue: 0.92)
        case .hurricane: Color(red: 0.86, green: 0.20, blue: 0.62)
        case .winterStorm: Color(red: 0.28, green: 0.78, blue: 0.95)
        case .heat: Color(red: 0.98, green: 0.45, blue: 0.40)
        case .airQuality: Color(red: 0.60, green: 0.46, blue: 0.31)
        case .earthquake: Color(red: 0.55, green: 0.36, blue: 0.24)
        case .landslide: Color(red: 0.47, green: 0.40, blue: 0.30)
        case .volcano: Color(red: 0.80, green: 0.22, blue: 0.10)
        case .drought: Color(red: 0.80, green: 0.62, blue: 0.25)
        case .injury: Color(red: 0.94, green: 0.33, blue: 0.53)
        case .other: Color(red: 0.42, green: 0.50, blue: 0.60)
        }
    }

    var symbol: String {
        switch self {
        case .fire: "flame.fill"
        case .smoke: "smoke.fill"
        case .tornado: "tornado"
        case .severeStorm: "cloud.bolt.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .flood: "water.waves"
        case .hurricane: "hurricane"
        case .winterStorm: "snowflake"
        case .heat: "thermometer.sun.fill"
        case .airQuality: "aqi.medium"
        case .earthquake: "waveform.path.ecg"
        case .landslide: "mountain.2.fill"
        case .volcano: "flame.circle.fill"
        case .drought: "sun.dust.fill"
        case .injury: "cross.case.fill"
        case .other: "exclamationmark.triangle.fill"
        }
    }

    /// Which incident type the map's Type filter treats it as.
    var filterType: IncidentType {
        switch self {
        case .fire: .fire
        case .smoke, .airQuality: .smoke
        case .tornado: .tornado
        case .severeStorm: .severeStorm
        case .heavyRain: .heavyRain
        case .flood: .flood
        case .hurricane: .hurricane
        case .winterStorm: .winterStorm
        case .injury: .injury
        case .heat, .other, .earthquake, .landslide, .volcano, .drought: .other
        }
    }
}

extension IncidentType {
    /// Community reports use the same colors as live hazards of the same kind.
    var hazardKind: HazardKind {
        HazardKind(rawValue: rawValue) ?? .other
    }

    var color: Color { hazardKind.color }
}

// MARK: - Zones and hazards

/// One danger zone: a circle around the center, or an exact outlined area.
struct HazardZone: Codable, Hashable {
    let level: ZoneLevel
    let radiusM: Int?
    let polygon: [[Double]]?   // [latitude, longitude] points

    var outline: [CLLocationCoordinate2D] {
        (polygon ?? []).compactMap { $0.count == 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
    }
}

extension Array where Element == HazardZone {
    /// Widest zone first, so the most dangerous one is drawn on top.
    var outsideIn: [HazardZone] { sorted { $0.level.rank < $1.level.rank } }
}

struct Hazard: Decodable, Identifiable, Hashable {
    let id: String
    let source: String
    let sourceLabel: String
    let kind: HazardKind
    let title: String
    let detail: String
    let level: ZoneLevel
    let latitude: Double
    let longitude: Double
    let zones: [HazardZone]
    let observedAt: Date?
    let endsAt: Date?
    let link: String?
    let isDemo: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var linkURL: URL? { link.flatMap(URL.init(string:)) }

    var accessibilityDescription: String {
        let demo = isDemo ? "Demo. " : ""
        return "\(demo)\(title), \(level.title), from \(sourceLabel)."
    }
}

/// How one data source did on the last refresh.
struct HazardSource: Decodable, Hashable {
    let name: String
    let ok: Bool
    let count: Int
    let error: String?
}

/// The server's answer to GET /hazards.
struct HazardFeed: Decodable {
    let hazards: [Hazard]
    let sources: [HazardSource]
    let updatedAt: Date
    let note: String   // zones are estimates; follow official instructions
}
