//
//  Role.swift
//  RollCall
//
//  The three kinds of people who use RollCall. In this demo you pick one on
//  the welcome screen (there are no real accounts yet).
//

import Foundation

enum Role: String, Codable, CaseIterable, Identifiable {
    case resident, buddy, responder

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .resident: "Resident"
        case .buddy: "Volunteer buddy"
        case .responder: "Responder"
        }
    }

    /// "I'm a resident", as one phrase (word order differs between languages).
    var iAm: LocalizedStringResource {
        switch self {
        case .resident: "I'm a resident"
        case .buddy: "I'm a volunteer buddy"
        case .responder: "I'm a responder"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .resident: "Register your household so help knows to check on you."
        case .buddy: "Check on neighbors who asked for a buddy."
        case .responder: "See who still needs help during an emergency."
        }
    }

    var symbol: String {
        switch self {
        case .resident: "house.fill"
        case .buddy: "person.2.wave.2.fill"
        case .responder: "cross.case.fill"
        }
    }
}

/// Who the app is acting as. Sent to the server with every request, which
/// decides what this person is allowed to see (backend/app/privacy.py).
struct Viewer: Equatable {
    let role: Role
    let id: Int?   // household id for a resident, volunteer id for a buddy
}
