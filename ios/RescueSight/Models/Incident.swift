//
//  Incident.swift
//  RescueSight
//
//  Swift versions of the JSON the backend sends (see backend/app/schemas.py).
//  "Codable" lets Swift turn JSON into these structs automatically.
//  The server uses snake_case names (report_count); the API client converts
//  them to Swift's camelCase (reportCount) for us.
//

import CoreLocation
import Foundation

// MARK: - Fixed lists of values

enum IncidentType: String, Codable, CaseIterable, Identifiable {
    case fire, smoke, flood, injury, other

    var id: Self { self }

    /// Name shown in the app.
    var title: String {
        switch self {
        case .fire: "Fire"
        case .smoke: "Smoke"
        case .flood: "Flood"
        case .injury: "Injury"
        case .other: "Other"
        }
    }

    /// SF Symbol icon for this type.
    var symbol: String {
        switch self {
        case .fire: "flame.fill"
        case .smoke: "smoke.fill"
        case .flood: "water.waves"
        case .injury: "cross.case.fill"
        case .other: "exclamationmark.triangle.fill"
        }
    }
}

enum IncidentStatus: String, Codable, CaseIterable, Identifiable {
    case active, responding, resolved

    var id: Self { self }

    var title: String {
        switch self {
        case .active: "Active"
        case .responding: "Responding"
        case .resolved: "Resolved"
        }
    }

    /// An icon for each status, so status never depends on color alone.
    var symbol: String {
        switch self {
        case .active: "exclamationmark.circle.fill"
        case .responding: "arrow.triangle.turn.up.right.circle.fill"
        case .resolved: "checkmark.circle.fill"
        }
    }
}

enum PriorityLevel: String, Codable {
    case high, medium, low

    var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

// MARK: - Incident

/// One line of the "Why this priority?" list, e.g. "Fire confirmed by AI, +40".
struct PriorityFactor: Codable, Hashable {
    let label: String
    let points: Int
}

struct Priority: Codable, Hashable {
    let score: Int          // 0 to 100
    let level: PriorityLevel
    let factors: [PriorityFactor]
}

/// What the AI found across all of an incident's photos and videos.
struct AISummary: Codable, Hashable {
    let verified: Bool
    let analyzing: Bool
    let fireDetected: Bool
    let smokeDetected: Bool
    let peopleCount: Int
    let lowLightUsed: Bool
}

/// An incident as shown on the map and in lists.
struct IncidentSummary: Codable, Identifiable, Hashable {
    let id: Int
    let type: IncidentType
    let status: IncidentStatus
    let latitude: Double
    let longitude: Double
    let locationName: String
    let reportCount: Int
    let mediaCount: Int
    let firstReportedAt: Date
    let lastReportAt: Date
    let respondingAt: Date?
    let resolvedAt: Date?
    let priority: Priority
    let ai: AISummary
    let coverThumbnailUrl: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Size of the colored zone on the map, in meters. It grows with each
    /// merged report (400 m for one report, +150 m per extra, up to 1 km).
    var zoneRadius: CLLocationDistance {
        min(400 + 150 * Double(max(reportCount - 1, 0)), 1000)
    }

    /// Active, high-priority incidents get a gentle pulse on the map.
    var needsAttention: Bool {
        status == .active && priority.level == .high
    }

    /// What VoiceOver reads for this incident, e.g.
    /// "Fire, active, high priority, 3 reports. FM 1570 south of Greenville".
    var accessibilityDescription: String {
        let reports = reportCount == 1 ? "1 report" : "\(reportCount) reports"
        return "\(type.title), \(status.title), \(priority.level.title) priority, \(reports). \(locationName)"
    }
}
