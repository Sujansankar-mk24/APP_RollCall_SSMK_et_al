//
//  IncidentRow.swift
//  RollCall
//
//  One line in the incident log. From left to right: the priority score
//  (big, like a number on a log sheet), then what happened with its status
//  stamp, where, what the AI found, and how many reports.
//

import SwiftUI

struct IncidentRow: View {
    let incident: IncidentSummary

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            PriorityScore(priority: incident.priority)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: Spacing.s) {
                    Label(incident.type.title, systemImage: incident.type.symbol)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: Spacing.xs)
                    Group {
                        if incident.underReview {
                            Stamp(text: String(localized: "Needs review"), systemImage: "eye", color: Color(.systemOrange))
                        } else {
                            Stamp(text: incident.status.title, color: incident.status.color)
                        }
                    }
                    .fixedSize()
                }
                Text(incident.locationName)
                    .font(.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                aiLine
                metaLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheetRow()
        .opacity(incident.status == .resolved ? 0.6 : 1)   // resolved incidents fade back
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens incident details")
        .accessibilityIdentifier("incidentRow_\(incident.id)")
    }

    // MARK: - Pieces

    /// What the AI found, or why there's nothing to show yet.
    @ViewBuilder
    private var aiLine: some View {
        if incident.ai.analyzing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("AI is analyzing…")
            }
            .font(.callout.weight(.medium))
        } else if incident.ai.verified {
            Label(evidenceText, systemImage: "viewfinder")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if incident.type.canBeVerifiedByAI {
            Label("Not verified by AI yet", systemImage: "questionmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var evidenceText: String {
        var parts: [String] = []
        if incident.ai.fireDetected { parts.append("Fire") }
        if incident.ai.smokeDetected { parts.append("Smoke") }
        let people = incident.ai.peopleCount
        if people > 0 { parts.append(people == 1 ? "1 person" : "\(people) people") }
        if incident.ai.peopleDown > 0 { parts.append("\(incident.ai.peopleDown) may be down") }
        return parts.joined(separator: " · ")
    }

    /// "3 reports · last 40 min. ago"
    private var metaLine: some View {
        let reports = incident.reportCount == 1 ? "1 report" : "\(incident.reportCount) reports"
        let ago = incident.lastReportAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return Text("\(reports) · last \(ago)")
            .font(.sheetLabel)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var accessibilityText: String {
        var text = incident.accessibilityDescription
        text += " Priority score \(incident.priority.score) out of 100."
        if incident.ai.verified { text += " AI found: \(evidenceText)." }
        return text
    }
}

/// The big priority number at the start of a row, with its level next to a
/// dot colored by priority (red high, amber medium, gray low).
struct PriorityScore: View {
    let priority: Priority

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(priority.score)")
                .font(.system(.title, weight: .semibold))
                .monospacedDigit()
            HStack(spacing: 4) {
                Circle().fill(priority.level.color).frame(width: 8, height: 8)
                Text(priority.level.title)
                    .font(.sheetLabel)
                    .textCase(.uppercase)
                    .foregroundStyle(priority.level.color)
            }
        }
        .frame(width: 58, alignment: .leading)
        .accessibilityHidden(true)  // the row's label already says it
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach(PreviewData.incidents) { IncidentRow(incident: $0) }
    }
    .padding()
    .sheetPage()
}
