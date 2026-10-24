//
//  IncidentKPIs.swift
//  RollCall
//
//  The four numbers at the top of the Incidents tab. Each one is a simple
//  count over the incident list, so it's easy to explain:
//
//    Active ......... incidents nobody is responding to yet
//    People ......... the most people the AI has seen at each OPEN incident, added up
//    Unverified ..... open incidents with no AI evidence yet
//    Avg response ... average time from the first report to "responding"
//

import Foundation

struct IncidentKPIs: Equatable {
    let active: Int
    let responding: Int
    let people: Int          // people the AI detected across open incidents
    let peopleDown: Int      // ...of those, how many may be lying on the ground
    let unverified: Int
    let averageResponse: TimeInterval?   // seconds; nil if no one has responded yet
    let responseCount: Int               // how many incidents that average is based on

    init(_ incidents: [IncidentSummary]) {
        let open = incidents.filter { $0.status != .resolved }
        active = open.filter { $0.status == .active }.count
        responding = open.filter { $0.status == .responding }.count
        people = open.reduce(0) { $0 + $1.ai.peopleCount }
        peopleDown = open.reduce(0) { $0 + $1.ai.peopleDown }
        unverified = open.filter { !$0.ai.verified }.count

        // Time to response: from the first report to the moment a responder
        // marked the incident "responding" (including ones resolved since).
        let times = incidents.compactMap { incident -> TimeInterval? in
            guard let respondedAt = incident.respondingAt else { return nil }
            return max(respondedAt.timeIntervalSince(incident.firstReportedAt), 0)
        }
        responseCount = times.count
        averageResponse = times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
    }

    /// "31 min", "1 hr 5 min", or "None yet" when nobody has responded yet.
    var averageResponseText: String {
        guard let averageResponse else { return String(localized: "None yet") }
        return Duration.seconds(averageResponse)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }
}
