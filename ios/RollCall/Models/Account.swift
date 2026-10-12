//
//  Account.swift
//  RollCall
//
//  The signed-in person, as the server describes them (matches MeOut and
//  AuthOut in backend/app/schemas.py).
//

import Foundation

struct Me: Decodable, Equatable {
    let id: Int
    let name: String
    let email: String
    let isResponder: Bool
    let rollCallOptOut: Bool        // chose "Not now" for the roll call
    let householdId: Int?           // their household, if they joined the roll call
    let isVolunteer: Bool           // agreed to check on neighbors
    let community: MyCommunity?
    let isDemo: Bool

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

/// The community the person belongs to, or is asking to join.
struct MyCommunity: Decodable, Equatable {
    let id: Int
    let name: String
    let city: String
    let status: MemberStatus
    let isAdmin: Bool
}

enum MemberStatus: String, Codable {
    case pending    // asked to join; waiting for the admin
    case member
}

/// The server's answer to signing up or in.
struct AuthResponse: Decodable {
    let token: String
    let me: Me
}

/// A fictional account judges can open with one tap.
struct DemoAccount: Decodable, Identifiable, Hashable {
    let userId: Int
    let name: String
    let kind: Kind
    let detail: String      // e.g. "Greenville · Pecan Hollow"
    let featured: Bool      // shown as a one-tap button on the sign-in screen

    var id: Int { userId }

    enum Kind: String, Decodable {
        case resident, volunteer, responder

        var title: LocalizedStringResource {
            switch self {
            case .resident: "Resident"
            case .volunteer: "Volunteer buddy"
            case .responder: "Responder"
            }
        }

        var symbol: String {
            switch self {
            case .resident: "house.fill"
            case .volunteer: "person.2.wave.2.fill"
            case .responder: "cross.case.fill"
            }
        }
    }
}
