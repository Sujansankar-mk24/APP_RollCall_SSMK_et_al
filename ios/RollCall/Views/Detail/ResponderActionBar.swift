//
//  ResponderActionBar.swift
//  RollCall
//
//  The buttons pinned to the bottom of the detail sheet. Which buttons show
//  depends on where the incident is in its life:
//    active      -> [Resolve]  [Mark responding]
//    responding  -> [Mark resolved]
//    resolved    -> "Resolved 2 hr ago"  [Reopen]
//

import SwiftUI

struct ResponderActionBar: View {
    let summary: IncidentSummary
    let isWorking: Bool
    let onChange: (IncidentStatus) -> Void

    @State private var confirmingResolve = false

    var body: some View {
        HStack(spacing: Spacing.m) {
            switch summary.status {
            case .active:
                resolveButton(prominent: false, title: "Resolve", expands: false)
                Button { onChange(.responding) } label: {
                    buttonLabel("Mark responding", systemImage: IncidentStatus.responding.symbol)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(.systemOrange))
            case .responding:
                resolveButton(prominent: true, title: "Mark resolved", expands: true)
            case .resolved:
                if let resolvedAt = summary.resolvedAt {
                    Label {
                        Text("Resolved \(resolvedAt.formatted(.relative(presentation: .named)))")
                    } icon: {
                        Image(systemName: IncidentStatus.resolved.symbol)
                            .foregroundStyle(Color(.systemGreen))
                    }
                    .font(.app(.subheadline).weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { onChange(.active) } label: {
                    buttonLabel("Reopen", systemImage: "arrow.uturn.backward", expands: false)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .disabled(isWorking)
        .overlay {
            if isWorking { ProgressView() }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.s)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Divider() }
        .confirmationDialog("Mark this incident as resolved?", isPresented: $confirmingResolve,
                            titleVisibility: .visible) {
            Button("Mark resolved") { onChange(.resolved) }
        } message: {
            Text("It will turn gray on the map. You can reopen it later.")
        }
    }

    private func resolveButton(prominent: Bool, title: String, expands: Bool) -> some View {
        Button { confirmingResolve = true } label: {
            buttonLabel(title, systemImage: IncidentStatus.resolved.symbol, expands: expands)
        }
        .buttonStyle(ProminenceButtonStyle(prominent: prominent))
    }

    /// `expands`: stretch to fill the row (main action) or stay just big enough.
    private func buttonLabel(_ title: String, systemImage: String, expands: Bool = true) -> some View {
        Label(title, systemImage: systemImage)
            .font(.app(.body).weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: 28)
    }
}

/// Lets one button switch between the filled (main action) and tinted look.
struct ProminenceButtonStyle: PrimitiveButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if prominent {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(.borderedProminent)
        } else {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(.bordered)
        }
    }
}
