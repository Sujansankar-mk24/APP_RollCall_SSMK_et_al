//
//  AreaStatusActivity.swift
//  RollCall (app and widget)
//
//  The Lock Screen "live status", like live sports scores: what's going on
//  around you ("All clear", or "Fire 2.1 mi away"), with "I'm safe" and
//  "I need help" buttons that check you in without opening the app.
//
//  This file is shared by the app (which starts and updates the status)
//  and the widget extension (which draws it).
//

import ActivityKit
import AppIntents
import Foundation

nonisolated struct AreaStatusAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// "All clear near you" or "Fire 2.1 mi from you".
        var headline: String
        /// One more line: what it is, or what to do.
        var detail: String
        /// "clear", "watch" or "danger" (sets the color).
        var level: String
        /// The SF Symbol for the hazard.
        var symbol: String
        /// Your last check-in: "safe", "needs_help" or "".
        var checkIn: String
        var updatedAt: Date
    }

    /// The community name, or the town.
    var place: String
}

/// The "I'm safe" / "I need help" buttons on the Lock Screen. They run in
/// the app's process, so they can send the check-in to the server.
struct CheckInIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Check in"
    static let description = IntentDescription("Tell your buddy you're safe or need help.")

    @Parameter(title: "Safe")
    var safe: Bool

    init() {}
    init(safe: Bool) { self.safe = safe }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await LockScreenCheckIn.send(safe: safe)
        #endif
        return .result()
    }
}
