//
//  NotificationSettingsView.swift
//  RollCall
//
//  Settings > Notifications: turn on a warning when danger comes close, and
//  a live status on the Lock Screen (like live sports scores) with "I'm
//  safe" and "I need help" buttons.
//

import SwiftUI

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private var alerts: AlertsManager { AlertsManager.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    SheetTitle(title: "Notifications", kicker: String(localized: "Stay in the loop"))
                    toggleCard(
                        isOn: Binding(get: { alerts.notifiesNearbyDanger }, set: { on in Task { await set(on, \.notifiesNearbyDanger) } }),
                        symbol: "bell.badge.fill", color: Color(.systemRed),
                        title: "Danger near me",
                        text: "A notification when a fire, storm or flood comes close to you, with \"I'm safe\" and \"I need help\" right on it.",
                        identifier: "notifyDangerToggle")
                    toggleCard(
                        isOn: Binding(get: { alerts.showsLiveStatus }, set: { on in Task { await set(on, \.showsLiveStatus) } }),
                        symbol: "lock.iphone", color: Color(.systemBlue),
                        title: "Live status on the Lock Screen",
                        text: "Like live sports scores: shows \"All clear\" or what's near you, and lets you check in without unlocking.",
                        identifier: "liveStatusToggle")
                    lockScreenPreview
                    if alerts.permissionDenied {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Text("Notifications are turned off for RollCall in the iPhone's Settings.")
                                .font(.app(.callout)).foregroundStyle(.secondary)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                            }
                            .buttonStyle(InkButtonStyle(prominent: false))
                        }
                        .sheetBox()
                    }
                    SheetNote(text: "Warnings come while RollCall is open or was used recently. In a life-threatening emergency, call 911.",
                              systemImage: "info.circle")
                }
                .padding(Spacing.l)
            }
            .sheetPage()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeNotifications")
                }
                .flat()
            }
        }
    }

    private func set(_ on: Bool, _ keyPath: ReferenceWritableKeyPath<AlertsManager, Bool>) async {
        if on, keyPath == \AlertsManager.notifiesNearbyDanger {
            guard await alerts.requestPermission() else { return }
        }
        alerts[keyPath: keyPath] = on
        await alerts.refreshLiveStatus(place: "")
    }

    private func toggleCard(isOn: Binding<Bool>, symbol: String, color: Color, title: LocalizedStringKey,
                            text: LocalizedStringKey, identifier: String) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: symbol)
                    .font(.app(.headline))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(.headline))
                    Text(text).font(.app(.footnote)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheetBox(padding: Spacing.l)
        .accessibilityIdentifier(identifier)
    }

    /// What the Lock Screen status looks like.
    private var lockScreenPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.app(.title3).weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color(.systemOrange), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROLLCALL · GREENVILLE").font(.app(.caption2).weight(.bold)).tracking(1).foregroundStyle(.white.opacity(0.7))
                    Text("Grass fire, 2.1 mi away").font(.app(.headline)).foregroundStyle(.white)
                    Text("Open RollCall for what to do.").font(.app(.caption)).foregroundStyle(.white.opacity(0.8))
                }
            }
            HStack(spacing: 8) {
                Text("I'm safe").frame(maxWidth: .infinity, minHeight: 34).background(Color(.systemGreen), in: Capsule())
                Text("I need help").frame(maxWidth: .infinity, minHeight: 34).background(Color(.systemRed), in: Capsule())
            }
            .font(.app(.subheadline).weight(.semibold)).foregroundStyle(.white)
        }
        .padding(14)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityHidden(true)
        .overlay(alignment: .topTrailing) {
            Text("Preview").font(.app(.caption2).weight(.bold)).foregroundStyle(.white.opacity(0.6)).padding(10)
        }
    }
}
