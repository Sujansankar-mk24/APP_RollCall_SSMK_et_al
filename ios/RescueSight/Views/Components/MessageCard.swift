//
//  MessageCard.swift
//  RescueSight
//
//  A reusable card for "something to tell you" moments: errors and empty
//  results. Always says what happened in plain words and offers the action
//  that fixes it.
//

import SwiftUI

struct MessageCard: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var isWorking = false
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: Spacing.s) {
                        if isWorking {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(actionTitle)
                    }
                    .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking)
                .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 340)
        .floatingSurface(cornerRadius: Radius.panel)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    MessageCard(
        systemImage: "antenna.radiowaves.left.and.right.slash",
        title: APIError.serverUnreachable.title,
        message: APIError.serverUnreachable.message,
        actionTitle: "Try again",
        action: {}
    )
    .padding()
}
