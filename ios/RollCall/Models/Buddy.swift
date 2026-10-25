//
//  Buddy.swift
//  RollCall
//
//  Volunteer buddy requests (matches the buddy shapes in
//  backend/app/schemas.py). Nothing about a household is shared with a
//  volunteer until the resident accepts their request.
//

import Foundation

enum BuddyStatus: String, Decodable {
    case pending, active, declined
}

/// A volunteer asking to check on the resident.
struct BuddyRequestToMe: Decodable, Identifiable, Hashable {
    let id: Int
    let volunteerName: String
    let volunteerCity: String
    let sameCommunity: Bool
    let createdAt: Date
}

/// A request the volunteer sent: a neighbor they picked, or an address they typed.
struct BuddyRequestSent: Decodable, Identifiable, Hashable {
    let id: Int
    let label: String
    let status: BuddyStatus
    let createdAt: Date
}

/// A community neighbor who asked for a buddy. Only a first name and street:
/// enough to decide to help, nothing more.
struct NeighborWantingBuddy: Decodable, Identifiable, Hashable {
    let householdId: Int
    let firstName: String
    let street: String
    let city: String
    let people: Int
    let alreadyAsked: Bool
    /// They said they'd like someone to check on them.
    var askedForBuddy: Bool = false
    /// How many neighbors already check on them (more can).
    var buddyCount: Int = 0

    var id: Int { householdId }
}

/// What a volunteer types to find someone outside their community.
struct AddressInput: Encodable, Equatable {
    var address = ""
    var city = ""
    var zipCode = ""
}
