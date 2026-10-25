//
//  IncidentDetail.swift
//  RollCall
//
//  The full information about one incident, shown in the detail sheet:
//  everything in IncidentSummary, plus every report, photo/video (with its
//  AI results) and timeline event. Matches IncidentDetailOut in
//  backend/app/schemas.py.
//

import Foundation

struct Report: Codable, Identifiable, Hashable {
    let id: Int
    let description: String
    let latitude: Double
    let longitude: Double
    let createdAt: Date
}

enum MediaKind: String, Codable {
    case photo, video
}

enum AnalysisStatus: String, Codable {
    case pending, processing, done, failed

    /// Still waiting for the AI.
    var isInProgress: Bool { self == .pending || self == .processing }
}

/// What the AI found in ONE photo or video.
struct MediaAnalysis: Codable, Hashable {
    let status: AnalysisStatus
    let fireDetected: Bool
    let fireConfidence: Double    // 0.0 to 1.0
    let smokeDetected: Bool
    let smokeConfidence: Double
    let peopleCount: Int
    let peopleDown: Int
    let peopleNearFire: Int
    let lowLightUsed: Bool
    let brightness: Double?
    let detector: String?         // e.g. "basic detector"
    let framesAnalyzed: Int
    let annotatedUrl: String?     // the picture with detection boxes drawn on
    let analyzedAt: Date?
    let error: String?
    /// Does the photo show what was reported? (backend/app/ai/verify.py)
    /// nil while the AI is still working, or from an older server.
    var confirmsReport: Bool? = nil
    /// Why, in plain words: "The AI couldn't see fire or smoke in the photo..."
    var verdict: String? = nil

    /// Did the AI find anything at all?
    var foundSomething: Bool { fireDetected || smokeDetected || peopleCount > 0 }

    /// Short summary, e.g. "Fire 92% · 1 person" or "Nothing detected".
    var shortSummary: String {
        switch status {
        case .pending, .processing: return "Analyzing…"
        case .failed: return "Couldn't analyze"
        case .done:
            var parts: [String] = []
            if fireDetected { parts.append("Fire \(fireConfidence.formatted(.percent.precision(.fractionLength(0))))") }
            if smokeDetected { parts.append("Smoke \(smokeConfidence.formatted(.percent.precision(.fractionLength(0))))") }
            if peopleCount > 0 { parts.append(peopleCount == 1 ? "1 person" : "\(peopleCount) people") }
            if peopleDown > 0 { parts.append("\(peopleDown) may be down") }
            if peopleNearFire > 0 { parts.append("\(peopleNearFire) near flames") }
            return parts.isEmpty ? "Nothing detected" : parts.joined(separator: " · ")
        }
    }
}

/// A photo or video attached to an incident.
struct MediaItem: Codable, Identifiable, Hashable {
    let id: Int
    let reportId: Int?
    let kind: MediaKind
    let url: String
    let thumbnailUrl: String?
    let createdAt: Date
    let analysis: MediaAnalysis

    var fileURL: URL? { AppConfig.mediaURL(url) }
    var thumbnailURL: URL? { AppConfig.mediaURL(thumbnailUrl) }
    var annotatedURL: URL? { AppConfig.mediaURL(analysis.annotatedUrl) }
}

enum TimelineKind: String, Codable {
    case report
    case aiResult = "ai_result"
    case statusChange = "status_change"
    case camera
}

struct TimelineEvent: Codable, Identifiable, Hashable {
    let id: Int
    let kind: TimelineKind
    let message: String
    let createdAt: Date
}

/// Everything about one incident.
struct IncidentDetail: Decodable, Hashable {
    let summary: IncidentSummary
    let reports: [Report]
    let media: [MediaItem]
    let timeline: [TimelineEvent]

    private enum CodingKeys: String, CodingKey {
        case reports, media, timeline
    }

    /// The server sends one flat JSON object. The summary fields are read
    /// into an IncidentSummary, and the extra lists are read separately.
    init(from decoder: Decoder) throws {
        summary = try IncidentSummary(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reports = try container.decode([Report].self, forKey: .reports)
        media = try container.decode([MediaItem].self, forKey: .media)
        timeline = try container.decode([TimelineEvent].self, forKey: .timeline)
    }
}
