//
//  PreviewData.swift
//  RescueSight
//
//  Sample incidents used ONLY by Xcode's live previews (the canvas next to
//  the code). The real app always shows data from the backend.
//

#if DEBUG
import Foundation

enum PreviewData {
    static let incidents: [IncidentSummary] = [
        make(id: 1, type: .fire, status: .active, level: .high, score: 100, reports: 3,
             place: "FM 1570 south of Greenville", latitude: 33.0705, longitude: -96.1050),
        make(id: 2, type: .injury, status: .responding, level: .high, score: 75, reports: 2,
             place: "I-30 eastbound near Royse City", latitude: 32.98, longitude: -96.315),
        make(id: 3, type: .flood, status: .active, level: .low, score: 5, reports: 2,
             place: "Low-water crossing on Post Oak Creek, Sherman", latitude: 33.625, longitude: -96.61),
        make(id: 4, type: .smoke, status: .resolved, level: .medium, score: 30, reports: 1,
             place: "Railroad right-of-way east of Commerce", latitude: 33.247, longitude: -95.9),
    ]

    private static func make(id: Int, type: IncidentType, status: IncidentStatus, level: PriorityLevel,
                             score: Int, reports: Int, place: String,
                             latitude: Double, longitude: Double) -> IncidentSummary {
        IncidentSummary(
            id: id, type: type, status: status, latitude: latitude, longitude: longitude,
            locationName: place, reportCount: reports, mediaCount: 1,
            firstReportedAt: .now.addingTimeInterval(-5400), lastReportAt: .now.addingTimeInterval(-2400),
            respondingAt: nil, resolvedAt: nil,
            priority: Priority(score: score, level: level, factors: []),
            ai: AISummary(verified: score > 20, analyzing: false, fireDetected: type == .fire,
                          smokeDetected: false, peopleCount: 0, peopleDown: 0, peopleNearFire: 0,
                          lowLightUsed: false),
            coverThumbnailUrl: nil, liveFeed: false, liveFeedSimulated: false
        )
    }
}
#endif
