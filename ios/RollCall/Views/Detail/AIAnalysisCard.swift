//
//  AIAnalysisCard.swift
//  RollCall
//
//  What the AI found across all of this incident's photos and videos, plus
//  the pictures with detection boxes drawn on them ("AI view").
//

import SwiftUI

struct AIAnalysisCard: View {
    let detail: IncidentDetail
    /// Called when a picture is tapped, to open it full screen.
    let onOpen: (MediaItem) -> Void

    private var analyzed: [MediaItem] {
        detail.media.filter { $0.analysis.status == .done }
    }

    var body: some View {
        SectionCard(title: "AI analysis", systemImage: "viewfinder", trailingNote: verifiedNote) {
            if detail.media.isEmpty {
                Text("No photos or videos yet. When someone adds one, the AI checks it for fire, smoke and people.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if detail.summary.ai.analyzing {
                    HStack(spacing: Spacing.s) {
                        ProgressView()
                        Text("Analyzing new photos and videos…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if !failed.isEmpty {
                    Label {
                        Text(failed.count == 1
                             ? "1 file couldn't be analyzed: \(failed[0].analysis.error ?? "unknown error")"
                             : "\(failed.count) files couldn't be analyzed.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(.systemOrange))
                    }
                    .font(.subheadline)
                }
                verdictLine
                findings
                if !analyzed.isEmpty {
                    annotatedImages
                }
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var failed: [MediaItem] {
        detail.media.filter { $0.analysis.status == .failed }
    }

    private var verifiedNote: String? {
        guard !detail.media.isEmpty else { return nil }
        return detail.summary.ai.verified ? "Verified by AI" : "Not verified yet"
    }

    // MARK: - Findings

    private var findings: some View {
        VStack(spacing: 0) {
            findingRow("Fire", systemImage: "flame.fill",
                       value: detectedText(analyzed.contains { $0.analysis.fireDetected },
                                           confidence: analyzed.map(\.analysis.fireConfidence).max()),
                       highlighted: detail.summary.ai.fireDetected)
            Divider()
            findingRow("Smoke", systemImage: "smoke.fill",
                       value: detectedText(analyzed.contains { $0.analysis.smokeDetected },
                                           confidence: analyzed.map(\.analysis.smokeConfidence).max()),
                       highlighted: detail.summary.ai.smokeDetected)
            Divider()
            findingRow("People", systemImage: "person.2.fill",
                       value: peopleText,
                       highlighted: detail.summary.ai.peopleCount > 0)
            if detail.summary.ai.peopleDown > 0 {
                Divider()
                findingRow("May be down (possible injury)", systemImage: "figure.fall",
                           value: "\(detail.summary.ai.peopleDown)", highlighted: true)
            }
            if detail.summary.ai.peopleNearFire > 0 {
                Divider()
                findingRow("Near the flames", systemImage: "flame",
                           value: "\(detail.summary.ai.peopleNearFire)", highlighted: true)
            }
            Divider()
            findingRow("Low-light enhancement", systemImage: "moon.stars.fill",
                       value: detail.summary.ai.lowLightUsed ? "Used" : "Not needed",
                       highlighted: false)
        }
    }

    private func findingRow(_ title: String, systemImage: String, value: String, highlighted: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .fontWeight(highlighted ? .semibold : .regular)
                .foregroundStyle(highlighted ? .primary : .secondary)
                .monospacedDigit()
        }
        .font(.subheadline)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    /// Did any photo show the disaster that was reported? (People alone never count.)
    @ViewBuilder
    private var verdictLine: some View {
        let verdicts = analyzed.compactMap { item in item.analysis.confirmsReport.map { ($0, item.analysis.verdict ?? "") } }
        if let confirmed = verdicts.first(where: { $0.0 }) ?? verdicts.first {
            Label {
                Text(verbatim: confirmed.1.isEmpty
                     ? (confirmed.0 ? String(localized: "The photo shows what was reported.") : String(localized: "The photo doesn't show what was reported."))
                     : confirmed.1)
            } icon: {
                Image(systemName: confirmed.0 ? "checkmark.seal.fill" : "hourglass")
                    .foregroundStyle(confirmed.0 ? Color(.systemGreen) : Color(.systemOrange))
            }
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("aiVerdict")
        }
    }

    private func detectedText(_ detected: Bool, confidence: Double?) -> String {
        guard !analyzed.isEmpty else { return "Waiting" }
        guard detected, let confidence else { return "Not detected" }
        return "Detected · \(confidence.formatted(.percent.precision(.fractionLength(0))))"
    }

    private var peopleText: String {
        guard !analyzed.isEmpty else { return "Waiting" }
        switch detail.summary.ai.peopleCount {
        case 0: return "None seen"
        case 1: return "1 person"
        case let count: return "\(count) people"
        }
    }

    private var footnote: String {
        let detectors = Set(analyzed.compactMap(\.analysis.detector))
        let fireDetector = detectors.contains("basic detector") || detectors.isEmpty
            ? "a basic color-and-flicker detector"
            : detectors.sorted().joined(separator: ", ")
        return "People are found with YOLOv8. Fire and smoke use \(fireDetector). Counts are the most people seen in a single photo or video."
    }

    // MARK: - Annotated pictures

    private var annotatedImages: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.m) {
                ForEach(analyzed) { item in
                    Button { onOpen(item) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RemoteImage(url: item.annotatedURL)
                                .frame(width: 200, height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                .overlay(alignment: .topLeading) { aiTag(for: item) }
                            Text(item.analysis.shortSummary)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .frame(width: 200, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("AI view of \(item.kind.rawValue): \(item.analysis.shortSummary)")
                    .accessibilityHint("Opens full screen")
                }
            }
        }
        .scrollClipDisabled()
    }

    private func aiTag(for item: MediaItem) -> some View {
        Label(item.kind == .video ? "AI · best frame" : "AI view", systemImage: "viewfinder")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(.systemBackground).opacity(0.9), in: Capsule())
            .padding(6)
    }
}
