//
//  CommunityTabView.swift
//  RollCall
//
//  The Community tab: your neighborhood, on the roll-call sheet.
//    Not in one yet   search for yours and ask to join, or create it
//    Asked to join    waiting for the admin
//    Member           who's in it (like a roster); the admin approves new
//                     members and decides whether volunteers from outside
//                     may be buddies here
//  Only people in the same community can be buddies to each other, unless
//  the admin allows outside buddies.
//

import SwiftUI

struct CommunityTabView: View {
    @Environment(AuthStore.self) private var auth
    @State private var viewModel = CommunityViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let community = auth.me?.community {
                        if community.status == .pending {
                            PendingCommunityView(community: community, viewModel: viewModel)
                        } else {
                            MyCommunityView(communityID: community.id, viewModel: viewModel)
                                .id(community.id)
                        }
                    } else {
                        FindCommunityView(viewModel: viewModel)
                    }
                }
                .padding(Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .sheetPage()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccountButton() }
                ToolbarItem(placement: .topBarTrailing) { AppearanceToolbarMenu() }
            }
            .refreshable { await auth.refresh() }
            .alert("Couldn't do that", isPresented: Binding(
                get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.actionError?.message ?? "")
            }
        }
    }
}

private func memberCount(_ count: Int) -> String {
    count == 1 ? String(localized: "1 member") : String(localized: "\(count) members")
}

// MARK: - Not in a community yet

private struct FindCommunityView: View {
    @Bindable var viewModel: CommunityViewModel
    @Environment(AuthStore.self) private var auth
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SheetTitle(title: "Community", kicker: String(localized: "Find your neighborhood"))
            Text("Neighbors in the same community can check on each other in an emergency. Search for yours, or start it if it's not here yet.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass").font(.title3)
                TextField("Neighborhood name", text: $viewModel.query)
                    .font(.title3)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityIdentifier("communitySearch")
                if viewModel.isSearching { ProgressView() }
            }
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 54)
            .background(Color.paperRaised)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.ink).frame(height: 2) }
            .onChange(of: viewModel.query) { viewModel.queryChanged() }

            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Neighborhoods")
                if viewModel.results.isEmpty && !viewModel.isSearching {
                    Text(viewModel.query.trimmed.isEmpty ? "No communities yet." : "No community called \"\(viewModel.query.trimmed)\" yet.")
                        .font(.callout).foregroundStyle(.secondary)
                        .sheetRow()
                }
                ForEach(viewModel.results) { community in
                    HStack(spacing: Spacing.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(community.name).font(.title3.weight(.semibold))
                            Text("\(community.city) · \(memberCount(community.memberCount))")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Ask to join") { Task { await viewModel.join(community, auth: auth) } }
                            .buttonStyle(SmallInkButtonStyle())
                            .disabled(viewModel.isWorking)
                            .accessibilityIdentifier("join_\(community.id)")
                    }
                    .sheetRow()
                    .accessibilityElement(children: .contain)   // keeps "Ask to join" its own button
                }
            }

            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionLabel("Not here yet?")
                Button { isCreating = true } label: {
                    Label("Start a community", systemImage: "plus")
                }
                .buttonStyle(InkButtonStyle(prominent: false))
                .accessibilityIdentifier("createCommunity")
                SheetNote(text: "You'll be its admin: you approve who joins.")
            }
        }
        .task { await viewModel.search() }
        .sheet(isPresented: $isCreating) {
            CreateCommunitySheet(viewModel: viewModel)
                .sheetBrand()
        }
    }
}

private struct CreateCommunitySheet: View {
    @Bindable var viewModel: CommunityViewModel
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var city = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text("Use your neighborhood's name, like the one on the sign at its entrance. Neighbors will search for it to join.")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledField(label: "Neighborhood name", prompt: "e.g. Pecan Hollow", text: $name,
                                 identifier: "communityNameField")
                    LabeledField(label: "Town", prompt: "Greenville", text: $city,
                                 contentType: .addressCity, identifier: "communityCityField")
                }
                .padding(Spacing.l)
            }
            .sheetPage()
            .navigationTitle("Start a community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if await viewModel.create(name: name, city: city, auth: auth) { dismiss() }
                        }
                    }
                    .disabled(name.trimmed.count < 2 || city.trimmed.isEmpty || viewModel.isWorking)
                    .accessibilityIdentifier("confirmCreateCommunity")
                }
            }
        }
    }
}

// MARK: - Waiting for approval

private struct PendingCommunityView: View {
    let community: MyCommunity
    let viewModel: CommunityViewModel
    @Environment(AuthStore.self) private var auth

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SheetTitle(verbatim: community.name, kicker: community.city)
            Stamp(text: String(localized: "Waiting for approval"), systemImage: "hourglass", color: Color(.systemOrange))
                .padding(.vertical, Spacing.s)
            Text("Waiting to join \(community.name)")
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("pendingCommunity")
            Text("The community's admin will approve your request. Pull down to check again.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button("Cancel my request") {
                Task { await viewModel.leave(id: community.id, auth: auth) }
            }
            .buttonStyle(InkButtonStyle(prominent: false, destructive: true))
        }
    }
}

// MARK: - Member

private struct MyCommunityView: View {
    let communityID: Int
    let viewModel: CommunityViewModel
    @Environment(AuthStore.self) private var auth
    @State private var confirmsLeaving = false

    var body: some View {
        Group {
            switch viewModel.detail {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            case .failed(let error):
                SheetMessage(error: error, action: { Task { await viewModel.loadDetail(id: communityID) } })
            case .loaded(let community):
                content(community)
            }
        }
        .task { await viewModel.loadDetail(id: communityID) }
        .confirmationDialog("Leave this community?", isPresented: $confirmsLeaving, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await viewModel.leave(id: communityID, auth: auth) } }
        } message: {
            Text("You can ask to join again later.")
        }
    }

    private func content(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            header(community)
            if community.isAdmin {
                if !community.joinRequests.isEmpty { joinRequests(community) }
                adminSettings(community)
            }
            roster(community)
            Button("Leave community", role: .destructive) { confirmsLeaving = true }
                .font(.callout.weight(.semibold))
                .underline()
                .frame(maxWidth: .infinity, minHeight: minimumTapSize)
        }
    }

    private func header(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SheetTitle(verbatim: community.name,
                       kicker: "\(community.city) · \(memberCount(community.memberCount))")
            if community.isAdmin {
                Stamp(text: String(localized: "You're the admin"), systemImage: "star.fill")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("communityHeader")
    }

    private func joinRequests(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Asking to join")
            ForEach(community.joinRequests) { person in
                HStack(spacing: Spacing.m) {
                    Text(person.name).font(.title3.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: Spacing.s)
                    Button("Decline") { Task { await viewModel.answer(person, approve: false, in: community) } }
                        .buttonStyle(SmallInkButtonStyle(prominent: false))
                    Button("Approve") { Task { await viewModel.answer(person, approve: true, in: community) } }
                        .buttonStyle(SmallInkButtonStyle())
                        .accessibilityIdentifier("approve_\(person.userId)")
                }
                .disabled(viewModel.isWorking)
                .sheetRow()
            }
        }
    }

    private func adminSettings(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Admin settings")
            Toggle(isOn: Binding(
                get: { community.allowOutsideBuddies },
                set: { allowed in Task { await viewModel.setOutsideBuddies(allowed, in: community) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow buddies from outside").font(.title3.weight(.semibold))
                    Text("Let volunteers who aren't in \(community.name) offer to check on members by address. Members still decide whether to accept.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .sheetRow()
            .accessibilityIdentifier("outsideBuddiesToggle")
        }
    }

    /// The members, numbered like names on a roster.
    private func roster(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Members")
            ForEach(Array(community.members.enumerated()), id: \.element.id) { index, person in
                HStack(spacing: Spacing.m) {
                    Text(verbatim: String(format: "%02d", index + 1))
                        .font(.sheetLabel)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .leading)
                    Text(person.name).font(.body.weight(.medium))
                    Spacer()
                    if person.isAdmin {
                        Text("Admin").sheetLabelStyle().foregroundStyle(.secondary)
                    }
                }
                .sheetRow()
                .accessibilityElement(children: .combine)
            }
        }
    }
}
