//
//  TimelineSection.swift
//  RollCall
//
//  The incident's history: every report, AI result and status change,
//  newest first, joined by a thin line like a timeline.
//

import SwiftUI

struct TimelineSection: View {
    let events: [TimelineEvent]

    private var newestFirst: [TimelineEvent] { events.reversed() }

    var body: some View {
        SectionCard(title: "Timeline", systemImage: "clock.arrow.circlepath") {
            if events.isEmpty {
                Text("Nothing has happened yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(newestFirst.enumerated()), id: \.element.id) { index, event in
                        TimelineRow(event: event, isLast: index == newestFirst.count - 1)
                    }
                }
            }
        }
    }
}

private struct TimelineRow: View {
    let event: TimelineEvent
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            // Icon with a line running down to the next event.
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(tint, in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, isLast ? 0 : Spacing.l)
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch event.kind {
        case .report: "megaphone.fill"
        case .aiResult: "viewfinder"
        case .statusChange: "arrow.triangle.2.circlepath"
        case .camera: "video.fill"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .report: Color.themeAccent
        case .aiResult: Color(.systemIndigo)
        case .statusChange: Color(.systemGray)
        case .camera: Color(.systemTeal)
        }
    }

    /// "9:41 PM · 2 hr ago" today, or "Wed 11:10 PM · 1 day ago" for older events.
    private var timeText: String {
        let time = Calendar.current.isDateInToday(event.createdAt)
            ? event.createdAt.formatted(date: .omitted, time: .shortened)
            : event.createdAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        let ago = event.createdAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return "\(time) · \(ago)"
    }
}
