//
//  AlertsManager.swift
//  RollCall
//
//  Notifications and the Lock Screen live status (Settings > Notifications):
//
//    Danger near me    a notification when a fire, storm or flood comes
//                      close to you, with "I'm safe" and "I need help"
//                      buttons right on it
//    Live status       a live status on the Lock Screen, like live sports
//                      scores: "All clear" or what's nearby, with the same
//                      two buttons
//
//  Both are off until the user turns them on. They update while RollCall is
//  open or was used recently. (Waking up a closed app needs push messages
//  from a server, which is out of scope for this project.)
//

import ActivityKit
import Foundation
import Observation
import UserNotifications

@Observable
final class AlertsManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertsManager()

    var notifiesNearbyDanger: Bool {
        didSet { UserDefaults.standard.set(notifiesNearbyDanger, forKey: "notifiesNearbyDanger") }
    }
    var showsLiveStatus: Bool {
        didSet { UserDefaults.standard.set(showsLiveStatus, forKey: "showsLiveStatus") }
    }
    private(set) var permissionDenied = false

    @ObservationIgnored private var lastState: AreaStatusAttributes.ContentState?
    @ObservationIgnored private var notified: Set<String> = []

    nonisolated static let categoryID = "CHECK_IN"
    nonisolated static let safeAction = "SAFE"
    nonisolated static let helpAction = "HELP"

    private override init() {
        notifiesNearbyDanger = UserDefaults.standard.bool(forKey: "notifiesNearbyDanger")
        showsLiveStatus = UserDefaults.standard.bool(forKey: "showsLiveStatus")
        super.init()
    }

    /// Called once when the app starts.
    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let safe = UNNotificationAction(identifier: Self.safeAction, title: String(localized: "I'm safe"), options: [])
        let help = UNNotificationAction(identifier: Self.helpAction, title: String(localized: "I need help"),
                                        options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.categoryID, actions: [safe, help],
                                                                 intentIdentifiers: [])])
    }

    /// Ask for permission (the iPhone's popup) the first time a switch is turned on.
    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        permissionDenied = !granted
        return granted
    }

    // MARK: - What's around you

    /// The map calls this whenever the nearest danger changes.
    func update(danger: NearbyDanger?, place: String) {
        let state = AreaStatusAttributes.ContentState(
            headline: danger.map { $0.isInside ? String(localized: "You're inside: \($0.title)") : String(localized: "\($0.title), \($0.distanceText) away") }
                ?? String(localized: "All clear near you"),
            detail: danger == nil ? String(localized: "No fires, storms or floods close by. RollCall is watching.")
                : String(localized: "Open RollCall for what to do. In a life-threatening emergency, call 911."),
            level: danger == nil ? "clear" : (danger!.isInside || danger!.meters < 3_000 ? "danger" : "watch"),
            symbol: danger?.kind.symbol ?? "checkmark.shield.fill",
            checkIn: lastState?.checkIn ?? "",
            updatedAt: .now)
        lastState = state
        if notifiesNearbyDanger, let danger, !notified.contains(danger.id) {
            notified.insert(danger.id)
            notify(about: danger)
        }
        Task { await refreshLiveStatus(place: place) }
    }

    private func notify(about danger: NearbyDanger) {
        let content = UNMutableNotificationContent()
        content.title = danger.isInside ? String(localized: "You're inside a hazard area") : String(localized: "\(danger.title) near you")
        content.body = danger.isInside ? danger.title : String(localized: "About \(danger.distanceText) away. Are you safe?")
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: danger.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Lock Screen

    func refreshLiveStatus(place: String) async {
        let activities = Activity<AreaStatusAttributes>.activities
        guard showsLiveStatus, let state = lastState ?? defaultState else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        if let activity = activities.first {
            await activity.update(ActivityContent(state: state, staleDate: .now.addingTimeInterval(60 * 60)))
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: AreaStatusAttributes(place: place),
                                      content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(60 * 60)))
        }
    }

    private var defaultState: AreaStatusAttributes.ContentState? {
        AreaStatusAttributes.ContentState(headline: String(localized: "Watching your area"),
                                          detail: String(localized: "Turn on Use my location on the Map to see what's near you."),
                                          level: "clear", symbol: "checkmark.shield.fill", checkIn: "", updatedAt: .now)
    }

    /// After a check-in from anywhere, show it on the Lock Screen too.
    func didCheckIn(safe: Bool, place: String) async {
        if var state = lastState ?? defaultState {
            state.checkIn = safe ? "safe" : "needs_help"
            lastState = state
        }
        await refreshLiveStatus(place: place)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show RollCall's notifications even while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// "I'm safe" / "I need help" tapped right on the notification.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        guard action == Self.safeAction || action == Self.helpAction else { return }
        await LockScreenCheckIn.send(safe: action == Self.safeAction)
    }
}

/// Sends a check-in from outside the app's screens (a notification button
/// or the Lock Screen), using the saved sign-in.
enum LockScreenCheckIn {
    static func send(safe: Bool) async {
        if APIClient.token == nil { APIClient.token = Keychain.loadToken() }
        _ = try? await APIClient.shared.checkIn(safe: safe)
        await AlertsManager.shared.didCheckIn(safe: safe, place: "")
    }
}
