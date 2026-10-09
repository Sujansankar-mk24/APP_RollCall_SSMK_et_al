//
//  KPICards.swift
//  RescueSight
//
//  The four number cards at the top of the Incidents tab. Each has a big
//  number, a label, and one line of context. A card turns red or amber when
//  its number means "someone needs help".
//

import SwiftUI

struct KPICards: View {
    let kpis: IncidentKPIs

    private let columns = [GridItem(.flexible(), spacing: Spacing.m), GridItem(.flexible(), spacing: Spacing.m)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.m) {
            KPICard(
                title: "Active incidents",
                value: "\(kpis.active)",
                caption: "\(kpis.responding) responding",
                systemImage: IncidentStatus.active.symbol,
                emphasis: kpis.active > 0 ? Color(.systemRed) : nil,
                identifier: "kpi_active"
            )
            KPICard(
                title: "People detected",
                value: "\(kpis.people)",
                caption: kpis.peopleDown > 0 ? "\(kpis.peopleDown) may be down" : "At open incidents",
                systemImage: "person.2.fill",
                emphasis: kpis.peopleDown > 0 ? Color(.systemRed) : nil,
                identifier: "kpi_people"
            )
            KPICard(
                title: "Unverified",
                value: "\(kpis.unverified)",
                caption: "No AI evidence yet",
                systemImage: "questionmark.circle.fill",
                emphasis: kpis.unverified > 0 ? Color(.systemOrange) : nil,
                identifier: "kpi_unverified"
            )
            KPICard(
                title: "Avg. response time",
                value: kpis.averageResponseText,
                caption: kpis.responseCount == 0
                    ? "No responses yet"
                    : "From \(kpis.responseCount) \(kpis.responseCount == 1 ? "incident" : "incidents")",
                systemImage: "stopwatch.fill",
                emphasis: nil,
                identifier: "kpi_response"
            )
        }
    }
}

struct KPICard: View {
    let title: String
    let value: String
    let caption: String
    let systemImage: String
    let emphasis: Color?   // red/amber when the number needs attention
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(emphasis ?? .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(alignment: .topTrailing) {
            // A small colored dot, so "needs attention" never depends on color
            // alone: the caption says why.
            if let emphasis {
                Circle().fill(emphasis).frame(width: 8, height: 8).padding(Spacing.m)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value). \(caption)")
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    KPICards(kpis: IncidentKPIs(PreviewData.incidents))
        .padding()
        .background(Color(.systemGroupedBackground))
}
