//
//  HazardDetailView.swift
//  RollCall
//
//  The sheet that opens when you tap a live hazard (a diamond on the map):
//  what it is, who reported it and when, its danger zones and what to do in
//  each, and a link to the official source.
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
                zones
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

    /// Each zone with its color swatch, size, and what to do there.
    private var zones: some View {
        SectionCard(title: "Danger zones", systemImage: "circle.circle") {
            ForEach(Array(hazard.zones.sorted { $0.level.rank > $1.level.rank }.enumerated()), id: \.offset) { _, zone in
                HStack(alignment: .top, spacing: Spacing.m) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hazard.kind.color.opacity(zone.level.fillOpacity * 2))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(hazard.kind.color, style: zone.level.edge))
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(zone.level.title).font(.headline)
                        Text(size(of: zone)).font(.callout).foregroundStyle(.secondary)
                        Text(zone.level.advice).font(.callout)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func size(of zone: HazardZone) -> String {
        if let radius = zone.radiusM {
            let distance = Measurement(value: Double(radius), unit: UnitLength.meters).converted(to: .miles)
            return "Within \(distance.formatted(.measurement(width: .abbreviated, usage: .road))) of the center"
        }
        if hazard.isDemo { return "The demo warning's area" }
        return hazard.source == "nws" ? "The area the National Weather Service drew" : "The marked area"
    }
}
