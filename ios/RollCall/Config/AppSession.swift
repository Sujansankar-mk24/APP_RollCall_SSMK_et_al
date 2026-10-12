//
//  AppSession.swift
//  RollCall
//
//  Remembers who the app is acting as: which role, and which household or
//  volunteer. Saved on the device, so the app opens where you left off.
//
//  (Debug tip: launch with "-RCRole resident -RCID 3" to start as household 3,
//  or "-RCRole responder". Launch arguments override the saved values.)
//

import Foundation
import Observation

@Observable
final class AppSession {
    private(set) var role: Role?
    private(set) var residentID: Int?
    private(set) var volunteerID: Int?

    private let defaults = UserDefaults.standard

    init() {
        role = defaults.string(forKey: "RCRole").flatMap(Role.init(rawValue:))
        let id = defaults.integer(forKey: "RCID")
        if id > 0 {
            if role == .resident { residentID = id }
            if role == .buddy { volunteerID = id }
        }
    }

    /// Who the server should treat this request as.
    var viewer: Viewer? {
        switch role {
        case .resident: residentID.map { Viewer(role: .resident, id: $0) }
        case .buddy: volunteerID.map { Viewer(role: .buddy, id: $0) }
        case .responder: Viewer(role: .responder, id: nil)
        case nil: nil
        }
    }

    func becomeResident(householdID: Int) { save(role: .resident, id: householdID) }
    func becomeBuddy(volunteerID: Int) { save(role: .buddy, id: volunteerID) }
    func becomeResponder() { save(role: .responder, id: nil) }

    /// Back to the welcome screen to pick a different role.
    func switchRole() { save(role: nil, id: nil) }

    private func save(role: Role?, id: Int?) {
        self.role = role
        residentID = role == .resident ? id : nil
        volunteerID = role == .buddy ? id : nil
        defaults.set(role?.rawValue, forKey: "RCRole")
        defaults.set(id ?? 0, forKey: "RCID")
    }
}
