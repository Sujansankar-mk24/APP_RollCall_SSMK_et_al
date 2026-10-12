//
//  MapFilters.swift
//  RollCall
//
//  The choices in the filter chips at the top of the map, and the rule that
//  decides whether an incident passes them.
//

import Foundation

enum TimeWindow: String, CaseIterable, Identifiable {
    case day, week

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Last 24 hours"
        case .week: "Last 7 days"
        }
    }

    var shortTitle: String {
        switch self {
        case .day: "24 hours"
        case .week: "7 days"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        }
    }
}

struct MapFilters: Equatable {
    var types: Set<IncidentType> = Set(IncidentType.allCases)
    var statuses: Set<IncidentStatus> = Set(IncidentStatus.allCases)
    var timeWindow: TimeWindow = .week

    /// True when nothing is filtered out (used to hide the "Clear" chip).
    var isDefault: Bool { self == MapFilters() }

    /// Should this incident be shown? It must match every filter.
    func matches(_ incident: IncidentSummary, now: Date = .now) -> Bool {
        types.contains(incident.type)
            && statuses.contains(incident.status)
            && now.timeIntervalSince(incident.lastReportAt) <= timeWindow.duration
    }

    // MARK: Chip labels

    var typesLabel: String {
        // If exactly one whole group is selected, name the group.
        if let category = IncidentCategory.allCases.first(where: { Set($0.types) == types }), types.count > 1 {
            return category.title
        }
        return label(for: types, all: IncidentType.allCases, name: "Type", plural: "types") { $0.title }
    }

    var statusesLabel: String {
        label(for: statuses, all: IncidentStatus.allCases, name: "Status", plural: "statuses") { $0.title }
    }

    /// "Type" (nothing filtered), a mode name like "Severe weather",
    /// "Fire" (one picked), or "2 types".
    private func label<Item: Hashable>(for selected: Set<Item>, all: [Item], name: String, plural: String,
                                       title: (Item) -> String) -> String {
        if selected.count == all.count || selected.isEmpty { return name }
        if selected.count == 1, let only = selected.first { return title(only) }
        return "\(selected.count) \(plural)"
    }
}
