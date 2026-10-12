//
//  RollCallTabView.swift
//  RollCall
//
//  The Roll Call tab. It shows the right screen for whoever the app is acting
//  as: the "who are you?" picker first, then a resident's household, a
//  buddy's neighbors, or the responder's view.
//

import SwiftUI

struct RollCallTabView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            switch session.role {
            case .resident where session.residentID != nil:
                ResidentHomeView(householdID: session.residentID!)
                    .id(session.residentID)
            case .buddy where session.volunteerID != nil:
                BuddyHomeView(volunteerID: session.volunteerID!)
                    .id(session.volunteerID)
            case .responder:
                ResponderHomeView()
            default:
                WelcomeView()
            }
        }
        .animation(.snappy(duration: 0.3), value: session.role)
    }
}
