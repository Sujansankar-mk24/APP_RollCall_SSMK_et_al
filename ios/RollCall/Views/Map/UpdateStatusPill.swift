//
//  UpdateStatusPill.swift
//  RollCall
//
//  The small "Updated 12 sec ago" label, so people can trust the map is
//  live. If a refresh fails, it turns into a warning with a retry button
//  while the last downloaded incidents stay on the map.
//

import SwiftUI

struct UpdateStatusPill: View {
    let lastUpdated: Date?
    let refreshError: APIError?
    let isRefreshing: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if refreshError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(.systemOrange))
                updatedText(prefix: "Offline · updated")
                retryButton
            } else {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                }
                updatedText(prefix: "Updated")
            }
        }
        .font(.caption)
        .padding(.leading, 10)
        .padding(.trailing, refreshError != nil ? 2 : 10)
        .frame(minHeight: 28)
        .floatingSurface(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func updatedText(prefix: String) -> some View {
        if let lastUpdated {
            // style: .relative keeps counting up by itself ("12 sec", "1 min"...).
            Text("\(prefix) \(Text(lastUpdated, style: .relative)) ago")
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        } else {
            Text("Not updated yet")
        }
    }

    private var retryButton: some View {
        Button(action: onRetry) {
            Image(systemName: "arrow.clockwise")
                .fontWeight(.semibold)
                .frame(width: minimumTapSize, height: 28)
                .contentShape(Rectangle())
        }
        .disabled(isRefreshing)
        .accessibilityLabel("Try again")
    }
}

#Preview {
    VStack(spacing: Spacing.l) {
        UpdateStatusPill(lastUpdated: .now.addingTimeInterval(-12), refreshError: nil, isRefreshing: false) {}
        UpdateStatusPill(lastUpdated: .now.addingTimeInterval(-140), refreshError: .serverUnreachable,
                         isRefreshing: false) {}
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
