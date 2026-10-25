//
//  ReportSentToast.swift
//  RollCall
//
//  The confirmation shown after a report is sent, e.g.
//  "Added to existing incident (3 reports)". If a photo/video was attached,
//  it follows the AI live: "AI is checking your photo…" turns into what the
//  AI found a few seconds later. "View" opens the incident.
//

import SwiftUI

/// Where the AI is with the photo/video from the report just sent.
enum ReportAnalysisState: Equatable {
    case noMedia                 // nothing was attached
    case analyzing               // the AI is working on it
    case finished(MediaAnalysis) // results are in
    case unknown                 // took too long or couldn't check; results will still appear later
}

struct ReportSentToast: View {
    let result: ReportCreated
    let analysis: ReportAnalysisState
    /// nil while the report is under review (it isn't on the map to view yet).
    let onView: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color(.systemGreen))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Report sent")
                    .font(.subheadline.weight(.semibold))
                Text(result.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                analysisLine
                    .font(.footnote.weight(.medium))
                    .padding(.top, 2)
            }

            Spacer(minLength: Spacing.s)

            if let onView {
                Button("View", action: onView)
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: minimumTapSize, minHeight: minimumTapSize)
            }
        }
        .padding(.leading, Spacing.l)
        .padding(.trailing, Spacing.s)
        .padding(.vertical, Spacing.s)
        .floatingSurface(cornerRadius: Radius.card)
        .padding(.horizontal, Spacing.l)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("reportSentToast")
    }

    @ViewBuilder
    private var analysisLine: some View {
        switch analysis {
        case .noMedia:
            EmptyView()
        case .analyzing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("AI is checking your photo or video…")
            }
            .foregroundStyle(Color.themeAccent)
        case .finished(let analysis):
            Label(finishedText(analysis), systemImage: "viewfinder")
                .foregroundStyle(analysis.foundSomething ? Color.primary : Color.secondary)
        case .unknown:
            Label("AI results will appear on the incident shortly.", systemImage: "clock")
                .foregroundStyle(.secondary)
        }
    }

    private func finishedText(_ analysis: MediaAnalysis) -> String {
        switch analysis.status {
        case .failed: return "The AI couldn't read this file."
        default:
            return analysis.foundSomething
                ? "AI found: \(analysis.shortSummary)"
                : "AI didn't find fire, smoke or people."
        }
    }
}
