//
//  BuddyHomeView.swift
//  RollCall
//
//  The "I check on" part of the Roll Call tab, for volunteer buddies:
//    * neighbors who accepted you (full details, only because they said yes),
//    * people in your community who asked for a buddy (first name and street only),
//    * "Check on someone by address", for people outside your community,
//    * requests you've sent.
//  (Check-in statuses, calling and "I checked on them" arrive in step 6.)
//

import SwiftUI

struct BuddyHomeView: View {
    @Environment(AuthStore.self) private var auth
    @State private var viewModel = BuddyHomeViewModel()
    @State private var asksByAddress = false
    @State private var confirmsStopping = false

    var body: some View {
        content
            .task { await viewModel.load() }
            .sheet(isPresented: $asksByAddress) {
                AddressBuddySheet { address in await viewModel.ask(address: address) }
                    .sheetBrand()
            }
            .alert("Couldn't do that", isPresented: Binding(
                get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.actionError?.message ?? "")
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
            ProgressView("Loading your neighbors…").frame(maxWidth: .infinity, minHeight: 240)
        case .failed(let error):
            SheetMessage(error: error, action: { Task { await viewModel.retry() } })
        case .loaded(let residents):
            VStack(alignment: .leading, spacing: Spacing.xl) {
                section("Neighbors you check on",
                        "They accepted you, so you can see their details. Nobody else can see this list.") {
                    if residents.isEmpty {
                        emptyNote("No one yet. Offer to help a neighbor below.")
                    } else {
                        ForEach(residents) { residentCard($0) }
                    }
                }
                communitySection
                VStack(alignment: .leading, spacing: Spacing.m) {
                    SectionLabel("Someone outside your community")
                    Text("You'll need their exact address, and they decide whether to accept.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { asksByAddress = true } label: {
                        Label("Check on someone by address", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(InkButtonStyle(prominent: false))
                    .accessibilityIdentifier("askByAddress")
                }
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
            section("Asked for a buddy in \(community.name)",
                    "Only their first name and street are shown until they accept you.") {
                if viewModel.neighbors.isEmpty {
                    emptyNote("Everyone who asked already has a buddy.")
                } else {
                    ForEach(viewModel.neighbors) { neighborRow($0) }
                }
            }
        } else {
            SheetNote(text: "Join your neighborhood in the Community tab to see neighbors who asked for a buddy.",
                      systemImage: "house.and.flag.fill")
        }
    }

    private func neighborRow(_ neighbor: NeighborWantingBuddy) -> some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(neighbor.firstName).font(.title3.weight(.semibold))
                Text("\(neighbor.street), \(neighbor.city)").font(.callout).foregroundStyle(.secondary)
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

    private func residentCard(_ resident: Household) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(resident.contactName).font(.title3.weight(.semibold))
                Spacer()
                if resident.language == .es { Stamp(text: "Español", tilt: 0) }
            }
            Label("\(resident.address), \(resident.city)", systemImage: "mappin")
                .font(.callout).foregroundStyle(.secondary)
            TagChips(tags: resident.tags)
        }
        .sheetRow()
        .accessibilityElement(children: .combine)
    }

    private func sentRow(_ request: BuddyRequestSent) -> some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.label).font(.headline)
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
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title)
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Spacing.s)
            }
            RuleLine()
            content()
        }
    }

    private func emptyNote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary)
            .sheetRow()
    }
}

/// "Check on someone by address": type their exact address. The answer is
/// the same whether or not anyone lives there, so this can't be used to find
/// out who lives where.
struct AddressBuddySheet: View {
    let send: (AddressInput) async -> Bool
    @State private var address = AddressInput()
    @State private var isSending = false
    @State private var sent = false
    @Environment(\.dismiss) private var dismiss

    private var isComplete: Bool {
        !address.address.trimmed.isEmpty && !address.city.trimmed.isEmpty
            && address.zipCode.count == 5 && address.zipCode.allSatisfy(\.isNumber)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if sent {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            Stamp(text: String(localized: "Request sent"), systemImage: "paperplane.fill")
                                .padding(.vertical, Spacing.s)
                            Text("If someone at that address uses RollCall and accepts, they'll appear in your list. To protect their privacy, we can't tell you whether anyone lives there.")
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityIdentifier("buddyRequestSent")
                    } else {
                        Text("Type the exact address of the person you'd like to check on. They'll get a request and decide whether to accept. You won't see anything about them unless they do.")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        LabeledField(label: "Street address", prompt: "e.g. 1418 Pecan Hollow Dr", text: $address.address,
                                     contentType: .streetAddressLine1, identifier: "buddyAddressField")
                        HStack(alignment: .top, spacing: Spacing.m) {
                            LabeledField(label: "Town", prompt: "Greenville", text: $address.city,
                                         contentType: .addressCity, identifier: "buddyCityField")
                            LabeledField(label: "ZIP code", prompt: "75401", text: $address.zipCode,
                                         contentType: .postalCode, keyboard: .numberPad, identifier: "buddyZipField")
                                .frame(maxWidth: 130)
                        }
                    }
                }
                .padding(Spacing.l)
            }
            .sheetPage()
            .navigationTitle("Check on someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
                .flat()
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            Task {
                                isSending = true
                                sent = await send(address)
                                isSending = false
                            }
                        }
                        .disabled(!isComplete || isSending)
                        .accessibilityIdentifier("sendBuddyRequest")
                    }
                    .flat()
                }
            }
        }
    }
}
