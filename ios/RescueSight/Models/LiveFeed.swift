//
//  LiveFeed.swift
//  RescueSight
//
//  The drone / camera feed's status, matching LiveFeedOut in
//  backend/app/schemas.py.
//

import Foundation

/// What the AI sees in the drone feed right now.
struct LiveStats: Decodable, Equatable {
    let peopleCount: Int
    let peopleDown: Int        // may be lying on the ground (possible injury)
    let peopleNearFire: Int
    let fireDetected: Bool
    let fireConfidence: Double
    let fireCoverage: Double   // share of the view that is flames, 0 to 1
    let smokeDetected: Bool
    let lowLightUsed: Bool
}

struct LiveFeedStatus: Decodable, Equatable {
    let active: Bool
    let cameraConnected: Bool  // a real drone/camera stream is set up on the server
    let sourceLabel: String?
    let isDemo: Bool
    let startedAt: Date?
    let framesAnalyzed: Int
    let frameUrl: String?
    let now: LiveStats?
    let peakPeople: Int
    let peakPeopleDown: Int
    let peakPeopleNearFire: Int
    let fireSeen: Bool
    let snapshotsSaved: Int
    let error: String?

    /// True if a feed ran at some point (so there's a summary to show).
    var hasRun: Bool { startedAt != nil }
}
