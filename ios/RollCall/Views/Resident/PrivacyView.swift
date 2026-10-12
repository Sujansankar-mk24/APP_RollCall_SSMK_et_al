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
    @Environment(\.brand) private var brand
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
                VStack(spacing: Spacing.m) {
                    audienceCard(symbol: "person.fill", tint: brand, who: "You", when: "Always",
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
        .background(Color(.systemGroupedBackground))
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
        VStack(alignment: .leading, spacing: Spacing.s) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(brand)
                .accessibilityHidden(true)
            Text("Only what helps, only when it helps")
                .font(.title2.weight(.bold)).fontDesign(.rounded)
                .fixedSize(horizontal: false, vertical: true)
            Text("RollCall shares your information only with the people who need it to reach you, and only when they need it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func audienceCard(symbol: String, tint: Color, who: LocalizedStringKey, when: LocalizedStringKey,
                              what: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(who).font(.headline)
                Text(when)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                Text(what).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var collected: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("What RollCall keeps, and why").font(.headline)
            reason("Your address", "so responders can find you")
            reason("Who lives with you", "so they know how many people to look for")
            reason("Your needs", "so the right help comes first")
            reason("Your check-ins", "so nobody is missed")
            Text("Nothing else: no contacts, no location tracking, no ads.")
                .font(.footnote).foregroundStyle(.secondary).padding(.top, Spacing.xs)
        }
        .card()
    }

    private func reason(_ what: LocalizedStringKey, _ why: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(brand)
            Text("\(Text(what).bold()) \(Text(why))").font(.subheadline)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmingDelete = true } label: {
            HStack(spacing: Spacing.s) {
                if isDeleting { ProgressView() } else { Image(systemName: "trash.fill") }
                Text("Delete my data")
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Color(.systemRed))
        .disabled(isDeleting)
        .accessibilityIdentifier("deleteMyData")
    }
}
