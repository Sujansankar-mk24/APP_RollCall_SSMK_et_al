//
//  ProfileView.swift
//  RollCall
//
//  Your profile (from the gear): who's signed in, whether you're on the roll
//  call, whether you're a volunteer, your community, which server the app
//  uses, and Sign out.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let me = auth.me {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        header(me)
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SectionLabel("Your RollCall")
                            SheetCard {
                            row("house.fill", "Roll call", rollCallStatus(me))
                            if !me.isResponder {
                                row("person.2.wave.2.fill", "Volunteer buddy",
                                    me.isVolunteer ? "Yes, you check on neighbors" : "Not yet")
                                row("house.and.flag.fill", "Community", communityStatus(me))
                            }
                            row(auth.serverURL == ServerSettings.thisMac ? "desktopcomputer" : "network",
                                "Server", ServerSettings.displayName(for: auth.serverURL))
                            }
                        }
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            Button {
                                dismiss()
                                Task { await auth.signOut() }
                            } label: {
                                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                            .buttonStyle(InkButtonStyle(prominent: false, destructive: true))
                            .accessibilityIdentifier("signOut")
                            SheetNote(text: "You stay signed in on this phone until you sign out.")
                        }
                    }
                    .padding(Spacing.l)
                }
            }
            .sheetPage()
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("closeProfile")
                }
                .flat()
            }
        }
        .presentationBackground(Color.paper)
    }

    private func header(_ me: Me) -> some View {
        HStack(spacing: Spacing.m) {
            Text(initials(me.name))
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.paper)
                .frame(width: 64, height: 64)
                .background(Color.ink, in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: me.name).sheetEntryStyle(large: true)
                Text(verbatim: me.email).font(.body).foregroundStyle(.secondary)
                if me.isResponder {
                    Stamp(text: String(localized: "Responder"), systemImage: "cross.case.fill", tilt: 0)
                        .padding(.top, Spacing.xs)
                }
            }
        }
        .sheetBox()
        .accessibilityElement(children: .combine)
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol).font(.title3).frame(width: 32)
            Text(title).font(.body.weight(.semibold))
            Spacer()
            Text(verbatim: value).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .sheetRow()
        .accessibilityElement(children: .combine)
    }

    private func rollCallStatus(_ me: Me) -> String {
        if me.isResponder { return String(localized: "Responder account") }
        if me.householdId != nil { return String(localized: "You're on it") }
        return me.rollCallOptOut ? String(localized: "You chose not now") : String(localized: "Not joined yet")
    }

    private func communityStatus(_ me: Me) -> String {
        guard let community = me.community else { return String(localized: "None yet") }
        switch community.status {
        case .pending: return String(localized: "Waiting to join \(community.name)")
        case .member: return community.isAdmin ? String(localized: "\(community.name) (admin)") : community.name
        }
    }
}
