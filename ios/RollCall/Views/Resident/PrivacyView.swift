//
//  PrivacyView.swift
//  RollCall
//
//  Exactly who can see a resident's information, and when, plus "Delete my
//  data" that really deletes it. These rules are enforced by the server
//  (backend/app/privacy.py), not just hidden in the app.
//

import SwiftUI

struct PrivacyView: View {
    let household: Household
    let isDeleting: Bool
    /// Deletes everything on the server; true if it worked.
    let onDelete: () async -> Bool
    /// Runs after this screen closes, once the data is gone.
    let onDeleted: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Who can see it, and when")
                    audienceCard(symbol: "person.fill", tint: .ink, who: "You", when: "Always",
                                 what: "Everything in your profile. You can change it or delete it anytime.")
                    audienceCard(symbol: "person.2.wave.2.fill", tint: Color(.systemTeal), who: "Your volunteer buddy",
                                 when: household.buddy != nil ? "Because you accepted them" : "Only after you accept one",
                                 what: "Your name, address, phone, needs, and whether you've checked in.")
                    audienceCard(symbol: "cross.case.fill", tint: Color(.systemOrange), who: "Responders",
                                 when: "Only during an emergency in your area",
                                 what: "What they need to reach and help you: your address, who lives there, medical equipment, mobility, and your check-in.")
                    audienceCard(symbol: "eye.slash.fill", tint: .secondary, who: "Everyone else", when: "Never",
                                 what: "Other residents, other volunteers and the public never see your information. If you asked for a buddy, people in your community see only your first name and street. It is never sold or shared.")
                }
                collected
                deleteButton
            }
            .padding(Spacing.l)
        }
        .sheetPage()
        .navigationTitle("Your privacy")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete all of your data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                Task {
                    guard await onDelete() else { return }
                    dismiss()            // back to the Roll Call tab...
                    await onDeleted()    // ...which now offers to join again
                }
            }
            Button("Keep my data", role: .cancel) {}
        } message: {
            Text("Your household, needs and history are removed from RollCall right away. This can't be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SheetTitle(title: "Only what helps", kicker: String(localized: "Your privacy"))
            Text("RollCall shares your information only with the people who need it to reach you, and only when they need it.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func audienceCard(symbol: String, tint: Color, who: LocalizedStringKey, when: LocalizedStringKey,
                              what: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(who).font(.title3.weight(.semibold))
                Text(when).sheetLabelStyle()
                Text(what).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheetRow()
        .accessibilityElement(children: .combine)
    }

    private var collected: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("What RollCall keeps, and why")
            reason("Your address", "so responders can find you")
            reason("Who lives with you", "so they know how many people to look for")
            reason("Your needs", "so the right help comes first")
            reason("Your check-ins", "so nobody is missed")
            SheetNote(text: "Nothing else: no contacts, no location tracking, no ads.")
                .padding(.top, Spacing.m)
        }
    }

    private func reason(_ what: LocalizedStringKey, _ why: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Image(systemName: "checkmark").font(.body.weight(.heavy))
            Text("\(Text(what).bold()) \(Text(why))").font(.body)
        }
        .sheetRow()
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmingDelete = true } label: {
            HStack(spacing: Spacing.s) {
                if isDeleting { ProgressView() } else { Image(systemName: "trash.fill") }
                Text("Delete my data")
            }
        }
        .buttonStyle(InkButtonStyle(prominent: false, destructive: true))
        .disabled(isDeleting)
        .accessibilityIdentifier("deleteMyData")
    }
}
