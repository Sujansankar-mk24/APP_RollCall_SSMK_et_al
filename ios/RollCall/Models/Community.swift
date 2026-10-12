//
//  Community.swift
//  RollCall
//
//  Neighborhood communities (matches CommunityOut and CommunityDetailOut in
//  backend/app/schemas.py).
//

import Foundation

struct CommunitySummary: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let city: String
    let memberCount: Int
    let myStatus: MemberStatus?   // nil if you haven't asked to join
    let isAdmin: Bool
}

struct CommunityDetail: Decodable, Equatable {
    let id: Int
    let name: String
    let city: String
    let memberCount: Int
    let myStatus: MemberStatus?
    let isAdmin: Bool
    let allowOutsideBuddies: Bool
    let members: [CommunityMember]       // only filled in for members
    let joinRequests: [CommunityMember]  // only filled in for the admin
}

struct CommunityMember: Decodable, Identifiable, Hashable {
    let userId: Int
    let name: String
    let isAdmin: Bool
    let since: Date

    var id: Int { userId }
}
