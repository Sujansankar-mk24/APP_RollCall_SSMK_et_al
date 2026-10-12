//
//  CommunityTabView.swift
//  RollCall
//
//  The Community tab (purple): your neighborhood.
//    Not in one yet   search for yours and ask to join, or create it
//    Asked to join    waiting for the admin
//    Member           who's in it; the admin approves new members and decides
//                     whether volunteers from outside may be buddies here
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
                            PendingCommunityCard(community: community, viewModel: viewModel)
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Community")
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

// MARK: - Not in a community yet

private struct FindCommunityView: View {
    @Bindable var viewModel: CommunityViewModel
    @Environment(AuthStore.self) private var auth
    @Environment(\.brand) private var brand
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Find your neighborhood")
                    .font(.title2.weight(.bold)).fontDesign(.rounded)
                Text("Neighbors in the same community can check on each other in an emergency. Search for yours, or start it if it's not here yet.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Neighborhood name", text: $viewModel.query)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityIdentifier("communitySearch")
                if viewModel.isSearching { ProgressView() }
            }
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 50)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .onChange(of: viewModel.query) { viewModel.queryChanged() }

            if viewModel.results.isEmpty && !viewModel.isSearching {
                Text(viewModel.query.trimmed.isEmpty ? "No communities yet." : "No community called \"\(viewModel.query.trimmed)\" yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(viewModel.results) { community in
                HStack(spacing: Spacing.m) {
                    Image(systemName: "house.and.flag.fill")
                        .foregroundStyle(brand)
                        .frame(width: 40, height: 40)
                        .background(brand.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(community.name).font(.headline)
                        Text("\(community.city) · \(community.memberCount) \(community.memberCount == 1 ? "member" : "members")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Ask to join") { Task { await viewModel.join(community, auth: auth) } }
                        .fixedSize()
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isWorking)
                        .accessibilityIdentifier("join_\(community.id)")
                }
                .card(padding: Spacing.m)
                .accessibilityElement(children: .contain)   // keeps "Ask to join" its own button
            }

            Button { isCreating = true } label: {
                Label("Start a community", systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("createCommunity")
            Text("You'll be its admin: you approve who joins.")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .task { await viewModel.search() }
        .sheet(isPresented: $isCreating) {
            CreateCommunitySheet(viewModel: viewModel)
                .rollCallBrand()
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
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledField(label: "Neighborhood name", prompt: "e.g. Pecan Hollow", text: $name,
                                 identifier: "communityNameField")
                    LabeledField(label: "Town", prompt: "Greenville", text: $city,
                                 contentType: .addressCity, identifier: "communityCityField")
                }
                .padding(Spacing.l)
            }
            .background(Color(.systemGroupedBackground))
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

private struct PendingCommunityCard: View {
    let community: MyCommunity
    let viewModel: CommunityViewModel
    @Environment(AuthStore.self) private var auth
    @Environment(\.brand) private var brand

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Image(systemName: "hourglass")
                .font(.largeTitle)
                .foregroundStyle(brand)
            Text("Waiting to join \(community.name)")
                .font(.title2.weight(.bold)).fontDesign(.rounded)
                .accessibilityIdentifier("pendingCommunity")
            Text("The community's admin will approve your request. Pull down to check again.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Cancel my request", role: .destructive) {
                Task { await viewModel.leave(id: community.id, auth: auth) }
            }
            .frame(minHeight: minimumTapSize)
        }
        .card()
    }
}

// MARK: - Member

private struct MyCommunityView: View {
    let communityID: Int
    let viewModel: CommunityViewModel
    @Environment(AuthStore.self) private var auth
    @Environment(\.brand) private var brand
    @State private var confirmsLeaving = false

    var body: some View {
        Group {
            switch viewModel.detail {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            case .failed(let error):
                MessageCard(error: error, action: { Task { await viewModel.loadDetail(id: communityID) } })
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
            members(community)
            Button("Leave community", role: .destructive) { confirmsLeaving = true }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: minimumTapSize)
        }
    }

    private func header(_ community: CommunityDetail) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "house.and.flag.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(brand, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(community.name).font(.title2.weight(.bold)).fontDesign(.rounded)
                Text("\(community.city) · \(community.memberCount) \(community.memberCount == 1 ? "member" : "members")")
                    .font(.subheadline).foregroundStyle(.secondary)
                if community.isAdmin {
                    Badge(text: "You're the admin", systemImage: "star.fill", color: brand)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("communityHeader")
    }

    private func joinRequests(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Asking to join").font(.title3.weight(.semibold)).fontDesign(.rounded)
            ForEach(community.joinRequests) { person in
                HStack(spacing: Spacing.m) {
                    avatar(person.name)
                    Text(person.name).font(.headline).lineLimit(2)
                    Spacer(minLength: Spacing.s)
                    Button("Decline") { Task { await viewModel.answer(person, approve: false, in: community) } }
                        .buttonStyle(.bordered)
                        .fixedSize()
                    Button("Approve") { Task { await viewModel.answer(person, approve: true, in: community) } }
                        .buttonStyle(.borderedProminent)
                        .fixedSize()
                        .accessibilityIdentifier("approve_\(person.userId)")
                }
                .disabled(viewModel.isWorking)
                .card(padding: Spacing.m)
            }
        }
    }

    private func adminSettings(_ community: CommunityDetail) -> some View {
        Toggle(isOn: Binding(
            get: { community.allowOutsideBuddies },
            set: { allowed in Task { await viewModel.setOutsideBuddies(allowed, in: community) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow buddies from outside").font(.headline)
                Text("Let volunteers who aren't in \(community.name) offer to check on members by address. Members still decide whether to accept.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: Spacing.m)
        .accessibilityIdentifier("outsideBuddiesToggle")
    }

    private func members(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Members").font(.title3.weight(.semibold)).fontDesign(.rounded)
            VStack(spacing: 0) {
                ForEach(Array(community.members.enumerated()), id: \.element.id) { index, person in
                    if index > 0 { Divider().padding(.leading, 60) }
                    HStack(spacing: Spacing.m) {
                        avatar(person.name)
                        Text(person.name).font(.body)
                        Spacer()
                        if person.isAdmin {
                            Text("Admin").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, Spacing.s)
                    .accessibilityElement(children: .combine)
                }
            }
            .card(padding: Spacing.m)
        }
    }

    private func avatar(_ name: String) -> some View {
        Text(initials(name))
            .font(.subheadline.weight(.bold)).fontDesign(.rounded)
            .foregroundStyle(brand)
            .frame(width: 36, height: 36)
            .background(brand.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}
