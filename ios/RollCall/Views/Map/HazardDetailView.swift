//
//  HazardDetailView.swift
//  RollCall
//
//  The sheet that opens when you tap a live hazard (a diamond on the map):
//  what it is, who reported it and when, how serious it is and what to do,
//  and a link to the official source.
//

import SwiftUI

struct HazardDetailView: View {
    let hazard: Hazard
    let note: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                Text(hazard.detail)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                whatToDo
                if let url = hazard.linkURL {
                    Link(destination: url) {
                        Label("Official details", systemImage: "arrow.up.right.square")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Label(note, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.l)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: hazard.kind.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(hazard.kind.color, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Spacing.s) {
                    Text(hazard.title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if hazard.isDemo {
                        Badge(text: "Demo", systemImage: "theatermasks.fill", color: .secondary)
                    }
                }
                Label(hazard.sourceLabel, systemImage: hazard.isDemo ? "theatermasks" : "dot.radiowaves.left.and.right")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                timeLine
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var timeLine: some View {
        let seen = hazard.observedAt.map { "Seen \($0.formatted(.relative(presentation: .named)))" }
        let ends = hazard.endsAt.map { "until \($0.formatted(date: .omitted, time: .shortened))" }
        let parts = [seen, ends].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: ", "))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// How serious it is, in one line: "Immediate danger: get away or take shelter now."
    private var whatToDo: some View {
        Label {
            Text("\(Text(hazard.level.title).bold()): \(hazard.level.advice.lowercasedFirst)")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(hazard.kind.color)
        }
        .font(.body)
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hazard.kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private extension String {
    /// "Get away now." -> "get away now." (to follow a colon).
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
