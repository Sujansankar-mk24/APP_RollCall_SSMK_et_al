//
//  RollCallTabView.swift
//  RollCall
//
//  The Roll Call tab. Responders see their view. Everyone else switches
//  between two parts of their sheet with the tabs under the title:
//    My household  join the roll call (or choose "Not now"), then your home,
//                  your buddy, and your privacy
//    I check on    be a volunteer buddy for neighbors
//

import SwiftUI

struct RollCallTabView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        if let me = auth.me, me.isResponder {
            ResponderHomeView()
        } else if let me = auth.me {
            MemberRollCallView(me: me)
        }
    }
}

private struct MemberRollCallView: View {
    let me: Me
    @Environment(AuthStore.self) private var auth
    @State private var section: Section = .household
    @State private var isJoining = false
    @State private var isWorking = false
    @State private var actionError: APIError?

    enum Section: Hashable { case household, buddy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    SheetTitle(title: "Roll Call", kicker: kicker)
                        .overlay(alignment: .topTrailing) { SettingsButton() }
                    SheetTabs(selection: $section,
                              options: [(value: .household, title: String(localized: "My household")),
                                        (value: .buddy, title: String(localized: "I check on"))],
                              identifiers: ["section_household", "section_buddy"])

                    switch section {
                    case .household: householdSection
                    case .buddy: buddySection
                    }
                }
                .padding(Spacing.l)
            }
            .sheetPage()
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await auth.refresh() }
        }
        .fullScreenCover(isPresented: $isJoining) {
            ProfileWizardView(mode: .register, existing: nil, name: me.name) { _ in
                Task { await auth.refresh() }
            }
            .sheetBrand()
        }
        .alert("Couldn't do that", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError?.message ?? "")
        }
    }

    /// The line above the title, like the header of a printed sheet:
    /// "PECAN HOLLOW · OCT 13".
    private var kicker: String {
        let date = Date.now.formatted(.dateTime.month(.abbreviated).day())
        if let community = me.community, community.status == .member {
            return "\(community.name) · \(date)"
        }
        return date
    }

    // MARK: - My household

    @ViewBuilder
    private var householdSection: some View {
        if let householdID = me.householdId {
            ResidentHomeView(householdID: householdID)
                .id(householdID)
        } else if me.rollCallOptOut {
            optedOut
        } else {
            joinInvitation
        }
    }

    /// Asking, not assuming: join now, or "Not now".
    private var joinInvitation: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Join the roll call?")
                .font(.sheetHeading)
            Text("When an emergency hits your area, RollCall asks if you're safe. If you don't answer, a neighbor checks on you, and responders know who still needs help.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            SheetCard {
                point("lock.fill", "Your details stay private until there's an emergency in your area.")
                point("hand.raised.fill", "It's your choice. You can leave anytime, and your data is deleted.")
                point("clock.fill", "Takes about 2 minutes.")
            }
            Button("Join the roll call") { isJoining = true }
                .buttonStyle(InkButtonStyle())
                .accessibilityIdentifier("joinRollCall")
            Button("Not now") { Task { await setOptOut(true) } }
                .buttonStyle(InkButtonStyle(prominent: false))
                .disabled(isWorking)
                .accessibilityIdentifier("notNow")
            SheetNote(text: "You can still use the Map and report incidents without joining.")
        }
    }

    private var optedOut: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Stamp(text: String(localized: "Not on the roll call"), systemImage: "xmark", color: .secondary)
                .accessibilityIdentifier("optedOut")
                .padding(.vertical, Spacing.s)
            Text("Responders won't know to check on you during an emergency. You can join anytime.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button("Join the roll call") { isJoining = true }
                .buttonStyle(InkButtonStyle())
                .accessibilityIdentifier("joinRollCall")
        }
    }

    private func point(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: symbol)
        }
        .font(.body)
        .sheetRow()
    }

    // MARK: - I check on

    @ViewBuilder
    private var buddySection: some View {
        if me.isVolunteer {
            BuddyHomeView()
        } else {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Be a volunteer buddy")
                    .font(.sheetHeading)
                Text("Check on neighbors who might need help in an emergency, like seniors living alone. You only see someone's details after they accept you.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Become a volunteer buddy") {
                    Task {
                        isWorking = true
                        defer { isWorking = false }
                        do throws(APIError) { try await auth.setVolunteer(true, city: me.community?.city ?? "") } catch { actionError = error }
                    }
                }
                .buttonStyle(InkButtonStyle())
                .disabled(isWorking)
                .accessibilityIdentifier("becomeVolunteer")
            }
        }
    }

    private func setOptOut(_ optOut: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do { try await auth.setRollCallOptOut(optOut) } catch { actionError = error }
    }
}
