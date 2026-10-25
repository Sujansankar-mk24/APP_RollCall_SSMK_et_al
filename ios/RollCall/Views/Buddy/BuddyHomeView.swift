//
//  BuddyHomeView.swift
//  RollCall
//
//  The "I check on" part of the Roll Call tab, for volunteer buddies:
//    * neighbors who accepted you (full details, only because they said yes),
//    * everyone else in your community on the roll call, so you can offer to
//      check on them too (first name and street only). Anyone can check on
//      anyone, and a household can have several buddies.
//    * requests you've sent.
//  You can also offer to be someone's buddy from their profile. Buddies only
//  come from your own community.
//

import SwiftUI

struct BuddyHomeView: View {
    @Environment(AuthStore.self) private var auth
    @State private var viewModel = BuddyHomeViewModel()
    @State private var confirmsStopping = false
    @State private var openPerson: Int?
    @State private var emergencyFor: Household?
    @Environment(\.openURL) private var openURL

    var body: some View {
        content
            .task { await viewModel.load() }
            .alert("Couldn't do that", isPresented: Binding(
                get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.actionError?.message ?? "")
            }
            .sheet(item: $openPerson) { id in PersonProfileView(personID: id).sheetBrand() }
            .fullScreenCover(item: $emergencyFor) { resident in
                EmergencyHelpView(name: resident.displayName, address: "\(resident.address), \(resident.city) \(resident.zipCode)",
                                  facts: resident.dispatcherFacts,
                                  emergencyContact: resident.emergencyContactPhone.isEmpty ? nil
                                      : (resident.emergencyContactName, resident.emergencyContactPhone))
                .sheetBrand()
            }
            .confirmationDialog("Stop being a volunteer buddy?", isPresented: $confirmsStopping, titleVisibility: .visible) {
                Button("Stop volunteering", role: .destructive) { Task { try? await auth.setVolunteer(false) } }
            } message: {
                Text("The neighbors you check on will no longer be matched with you.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingView(text: "Loading your neighbors…")
        case .failed(let error):
            SheetMessage(error: error, action: { Task { await viewModel.retry() } })
        case .loaded(let residents):
            VStack(alignment: .leading, spacing: Spacing.xl) {
                section("Neighbors you check on",
                        "They accepted you, so you can see their details. Nobody else can see this list.") {
                    if residents.isEmpty {
                        emptyNote("No one yet. Offer to help a neighbor below, or from their profile in Community.")
                    } else {
                        ForEach(residents) { residentCard($0) }
                    }
                }
                communitySection
                if !viewModel.sent.isEmpty {
                    section("Requests you sent", nil) {
                        ForEach(viewModel.sent) { sentRow($0) }
                    }
                }
                Button("Stop volunteering", role: .destructive) { confirmsStopping = true }
                    .font(.callout.weight(.semibold))
                    .underline()
                    .frame(maxWidth: .infinity, minHeight: minimumTapSize)
            }
        }
    }

    // MARK: - Community neighbors

    @ViewBuilder
    private var communitySection: some View {
        if let community = auth.me?.community, community.status == .member {
            section("Neighbors in \(community.name)",
                    "Offer to check on anyone here, even if someone already does. Only their first name and street are shown until they accept you.") {
                if viewModel.neighbors.isEmpty {
                    emptyNote("You already check on everyone in your community who's on the roll call. When someone new joins, they'll show up here.")
                } else {
                    ForEach(viewModel.neighbors) { neighborRow($0) }
                }
            }
        } else {
            SheetNote(text: "Join your neighborhood in the Community tab to see neighbors you can check on.",
                      systemImage: "house.and.flag.fill")
        }
    }

    private func neighborRow(_ neighbor: NeighborWantingBuddy) -> some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: neighbor.firstName).sheetEntryStyle()
                Text(verbatim: "\(neighbor.street), \(neighbor.city)").font(.callout).foregroundStyle(.secondary)
                // Who needs someone most: asked for a buddy, or nobody checks on them yet.
                if neighbor.buddyCount == 0 && neighbor.askedForBuddy {
                    Text("Asked for a buddy").font(.footnote.weight(.semibold)).foregroundStyle(Color(.systemOrange))
                } else if neighbor.buddyCount > 0 {
                    Text(AttributedString(localized: "Checked on by ^[\(neighbor.buddyCount) neighbor](inflect: true)"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if neighbor.alreadyAsked {
                Stamp(text: String(localized: "Asked"), systemImage: "checkmark", color: .secondary)
            } else {
                Button("Offer to help") { Task { await viewModel.offer(to: neighbor) } }
                    .buttonStyle(SmallInkButtonStyle())
                    .disabled(viewModel.isWorking)
                    .accessibilityIdentifier("offer_\(neighbor.householdId)")
            }
        }
        .sheetRow()
        .accessibilityElement(children: .contain)
    }

    // MARK: - Rows

    /// A neighbor you check on: who they are, their needs, and quick ways to
    /// reach them (call, text, directions), plus "They need help".
    private func residentCard(_ resident: Household) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Button { openPerson = resident.ownerId } label: {
                HStack(spacing: Spacing.m) {
                    // Their name and picture as they are now (renames show up here too).
                    Avatar(url: resident.ownerPhotoURL, name: resident.displayName, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: resident.displayName).sheetEntryStyle()
                        Text(verbatim: "\(resident.address), \(resident.city)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if resident.checkIn == "needs_help" {
                        Stamp(text: String(localized: "Needs help"), systemImage: "exclamationmark.triangle.fill", color: Color(.systemRed))
                    } else if resident.checkIn == "safe" {
                        Stamp(text: String(localized: "Safe"), systemImage: "checkmark", color: Color(.systemGreen))
                    }
                    if resident.language == .es { Stamp(text: "Español") }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens their profile")
            TagChips(tags: resident.tags)
            HStack(spacing: Spacing.s) {
                if let digits = PersonProfileView.digits(resident.phone) {
                    quickAction("Call", "phone.fill") { open("tel:\(digits)") }
                        .accessibilityIdentifier("callResident")
                    quickAction("Text", "message.fill") { open("sms:\(digits)") }
                        .accessibilityIdentifier("textResident")
                }
                quickAction("Directions", "arrow.triangle.turn.up.right.diamond.fill") {
                    open("maps://?daddr=\(resident.latitude),\(resident.longitude)")
                }
            }
            Button { emergencyFor = resident } label: {
                Label("They need help", systemImage: "cross.case.fill")
            }
            .buttonStyle(InkButtonStyle(destructive: true))
            .accessibilityIdentifier("theyNeedHelp")
        }
        .sheetRow()
    }

    private func quickAction(_ title: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.headline)
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ link: String) {
        if let url = URL(string: link) { openURL(url) }
    }

    private func sentRow(_ request: BuddyRequestSent) -> some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: request.label).sheetEntryStyle()
                Text(request.status == .declined ? "They said no thanks" : "Waiting for them to accept")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(request.status == .declined ? "Remove" : "Cancel") {
                Task { await viewModel.cancel(requestID: request.id) }
            }
            .buttonStyle(SmallInkButtonStyle(prominent: false))
        }
        .sheetRow()
        .accessibilityElement(children: .contain)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey?,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel(title)
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SheetCard { content() }
        }
    }

    private func emptyNote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary)
            .sheetRow()
    }
}
