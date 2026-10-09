//
//  PriorityBreakdownCard.swift
//  RescueSight
//
//  "Why this priority?": every rule that added or removed points, so a
//  responder (or a judge!) can check exactly how the score was made.
//

import SwiftUI

struct PriorityBreakdownCard: View {
    let priority: Priority

    private var rawTotal: Int { priority.factors.reduce(0) { $0 + $1.points } }

    var body: some View {
        SectionCard(title: "Why this priority?", systemImage: "list.number") {
            VStack(spacing: 0) {
                ForEach(priority.factors, id: \.self) { factor in
                    HStack {
                        Text(factor.label)
                        Spacer()
                        Text(factor.points > 0 ? "+\(factor.points)" : "\(factor.points)")
                            .fontWeight(.semibold)
                            .foregroundStyle(factor.points < 0 ? Color(.systemRed) : .primary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    Divider()
                }

                HStack {
                    Text("Priority score")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(priority.score) / 100")
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .padding(.top, 10)
                .accessibilityElement(children: .combine)
            }

            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var note: String {
        var text = "Simple rules, not a black box: confirmed evidence counts most, and reports the AI hasn't verified rank lower."
        if rawTotal != priority.score {
            text += " The points add up to \(rawTotal), and scores are kept between 0 and 100."
        }
        return text
    }
}

#Preview {
    PriorityBreakdownCard(priority: Priority(score: 100, level: .high, factors: [
        PriorityFactor(label: "Fire report", points: 20),
        PriorityFactor(label: "Fire confirmed by AI", points: 40),
        PriorityFactor(label: "Smoke confirmed by AI", points: 20),
        PriorityFactor(label: "1 person detected by AI", points: 15),
        PriorityFactor(label: "2 more reports from the area", points: 10),
        PriorityFactor(label: "Low light / night", points: 5),
    ]))
    .padding()
    .background(Color(.systemGroupedBackground))
}
