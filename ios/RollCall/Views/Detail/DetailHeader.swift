//
//  DetailHeader.swift
//  RollCall
//
//  Top of the detail sheet: what it is, where, its status and priority,
//  and three quick facts (reports, time since first report, media).
//

import SwiftUI

struct DetailHeader: View {
    let summary: IncidentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                Image(systemName: summary.type.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(summary.status.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.type.title)
                        .font(.title2.weight(.bold))
                    Label(summary.locationName, systemImage: "mappin")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            // Badges wrap onto a second line if the text is very large.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s) { badges }
                VStack(alignment: .leading, spacing: Spacing.s) { badges }
            }

            HStack(spacing: 0) {
                fact(value: "\(summary.reportCount)",
                     label: summary.reportCount == 1 ? "report" : "reports")
                Divider().frame(height: 32)
                fact(value: summary.firstReportedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)),
                     label: "first report")
                Divider().frame(height: 32)
                fact(value: "\(summary.mediaCount)",
                     label: summary.mediaCount == 1 ? "photo/video" : "photos/videos")
            }
            .padding(.vertical, Spacing.s)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    @ViewBuilder
    private var badges: some View {
        StatusBadge(status: summary.status)
        PriorityBadge(priority: summary.priority)
    }

    private func fact(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DetailHeader(summary: PreviewData.incidents[0])
        .padding()
        .background(Color(.systemGroupedBackground))
}
