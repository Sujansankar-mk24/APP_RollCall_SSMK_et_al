//
//  ReportSentToast.swift
//  RescueSight
//
//  The short confirmation shown after a report is sent, e.g.
//  "Added to existing incident (3 reports)", with a button to open it.
//

import SwiftUI

struct ReportSentToast: View {
    let result: ReportCreated
    let onView: () -> Void

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
            }

            Spacer(minLength: Spacing.s)

            Button("View", action: onView)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: minimumTapSize, minHeight: minimumTapSize)
        }
        .padding(.leading, Spacing.l)
        .padding(.trailing, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .floatingSurface(cornerRadius: Radius.card)
        .padding(.horizontal, Spacing.l)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
