//
//  KPICards.swift
//  RollCall
//
//  The four number cards at the top of the Incidents tab (each one is a
//  KPICard, see Components/KPICard.swift).
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

#Preview {
    KPICards(kpis: IncidentKPIs(PreviewData.incidents))
        .padding()
        .background(Color(.systemGroupedBackground))
}
