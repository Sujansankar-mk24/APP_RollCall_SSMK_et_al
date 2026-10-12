//
//  IncidentRow.swift
//  RollCall
//
//  One incident in the priority list. From left to right: what it is (icon
//  colored by status), where, what the AI found, and the priority score.
//

import SwiftUI

struct IncidentRow: View {
    let incident: IncidentSummary

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: incident.type.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(incident.status.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: Spacing.s) {
                    Text(incident.type.title)
                        .font(.headline)
                    StatusBadge(status: incident.status)
                        .scaleEffect(0.85, anchor: .leading)
                        .fixedSize()
                        .frame(height: 24)
                }
                Text(incident.locationName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                aiLine
                metaLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PriorityScore(priority: incident.priority)
        }
        .padding(Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .opacity(incident.status == .resolved ? 0.72 : 1)   // resolved incidents fade back
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.accentColor)
        } else if incident.ai.verified {
            Label(evidenceText, systemImage: "viewfinder")
                .font(.footnote.weight(.medium))
        } else if incident.type.canBeVerifiedByAI {
            Label("Not verified by AI yet", systemImage: "questionmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private var accessibilityText: String {
        var text = incident.accessibilityDescription
        text += " Priority score \(incident.priority.score) out of 100."
        if incident.ai.verified { text += " AI found: \(evidenceText)." }
        return text
    }
}

/// The big number on the right of a row, tinted by priority level.
struct PriorityScore: View {
    let priority: Priority

    var body: some View {
        VStack(spacing: 0) {
            Text("\(priority.score)")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
            Text(priority.level.title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .frame(width: 58, height: 52)
        .background(priority.level.color.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityHidden(true)  // the row's label already says it
    }
}

#Preview {
    VStack(spacing: Spacing.m) {
        ForEach(PreviewData.incidents) { IncidentRow(incident: $0) }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
