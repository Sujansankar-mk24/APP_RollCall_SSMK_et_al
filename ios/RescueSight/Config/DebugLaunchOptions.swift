//
//  DebugLaunchOptions.swift
//  RescueSight
//
//  Helpers for taking screenshots and testing, available in Debug builds only.
//  Launch arguments become UserDefaults values, so you can start the app with:
//
//      xcrun simctl launch booted com.sujansankar.RescueSight -RSSelectIncident 1 -RSLargeSheet YES
//
//  (or add them in Xcode: Product > Scheme > Edit Scheme > Run > Arguments).
//

import Foundation

enum DebugLaunchOptions {
    /// Open this incident's detail sheet as soon as the map loads.
    static var incidentToSelect: Int? {
        #if DEBUG
        let id = UserDefaults.standard.integer(forKey: "RSSelectIncident")
        return id > 0 ? id : nil
        #else
        return nil
        #endif
    }

    /// Open the detail sheet at full height instead of half height.
    static var opensLargeSheet: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "RSLargeSheet")
        #else
        return false
        #endif
    }
}
