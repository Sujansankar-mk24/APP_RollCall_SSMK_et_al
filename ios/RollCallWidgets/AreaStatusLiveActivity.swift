//
//  AreaStatusLiveActivity.swift
//  RollCallWidgets
//
//  How the live status looks on the Lock Screen and in the Dynamic Island:
//  a colored icon, the headline ("Fire 2.1 mi from you"), one more line,
//  and two buttons, "I'm safe" and "I need help".
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct RollCallWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AreaStatusLiveActivity()
    }
}

struct AreaStatusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AreaStatusAttributes.self) { context in
            LockScreenStatus(state: context.state, place: context.attributes.place)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbol)
                        .font(.title2)
                        .foregroundStyle(color(context.state.level))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.headline).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CheckInButtons()
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(color(context.state.level))
            } compactTrailing: {
                Text(context.state.level == "clear" ? "Clear" : "Alert")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(context.state.level))
            } minimal: {
                Image(systemName: context.state.symbol).foregroundStyle(color(context.state.level))
            }
        }
    }
}

private func color(_ level: String) -> Color {
    switch level {
    case "danger": .red
    case "watch": .orange
    default: .green
    }
}

private struct LockScreenStatus: View {
    let state: AreaStatusAttributes.ContentState
    let place: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: state.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(color(state.level), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROLLCALL · \(place.uppercased())")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(state.headline).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(state.detail).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            CheckInButtons(checkIn: state.checkIn)
        }
        .padding(14)
    }
}

private struct CheckInButtons: View {
    var checkIn: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CheckInIntent(safe: true)) {
                Label(checkIn == "safe" ? "Safe ✓" : "I'm safe", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)
            Button(intent: CheckInIntent(safe: false)) {
                Label(checkIn == "needs_help" ? "Help sent ✓" : "I need help", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }
}
