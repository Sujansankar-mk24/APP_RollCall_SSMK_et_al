//
//  MessageCard.swift
//  RollCall
//
//  A reusable card for "something to tell you" moments: errors and empty
//  results. Always says what happened in plain words and offers the action
//  that fixes it.
//

import SwiftUI

struct MessageCard: View {
    let systemImage: String
    private let title: Text
    private let message: Text
    var actionTitle: LocalizedStringResource?
    var isWorking = false
    var action: (() -> Void)?

    init(systemImage: String, title: LocalizedStringResource, message: LocalizedStringResource,
         actionTitle: LocalizedStringResource? = nil, isWorking: Bool = false, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = Text(title)
        self.message = Text(message)
        self.actionTitle = actionTitle
        self.isWorking = isWorking
        self.action = action
    }

    /// For something that went wrong while talking to the server.
    init(error: APIError, actionTitle: LocalizedStringResource? = "Try again", isWorking: Bool = false,
         action: (() -> Void)? = nil) {
        self.systemImage = error == .serverUnreachable ? "antenna.radiowaves.left.and.right.slash" : "exclamationmark.triangle"
        self.title = Text(error.title)
        self.message = Text(verbatim: error.message)
        self.actionTitle = actionTitle
        self.isWorking = isWorking
        self.action = action
    }

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.xs) {
                title
                    .font(.app(.headline))
                message
                    .font(.app(.subheadline))
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
    MessageCard(error: .serverUnreachable, action: {})
    .padding()
}
