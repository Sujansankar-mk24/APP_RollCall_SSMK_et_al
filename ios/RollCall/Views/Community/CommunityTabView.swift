//
//  CommunityTabView.swift
//  RollCall
//
//  The Community tab: your neighborhood.
//    Not in one yet   search for yours (tap one to see its Weekly Recap) and
//                     ask to join, or start one and be its admin
//    Asked to join    waiting for the admin
//    Member           the Weekly Recap (photos from the neighborhood), who's
//                     in it, split by who has a buddy and who still needs
//                     one, first responders nearby, and other communities
//  Tap anyone to open their profile. Buddies come from the same community,
//  because a neighbor is the one who can get there fast.
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
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                SettingsButton().padding(.horizontal, Spacing.l).padding(.top, Spacing.l)
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

/// A community's picture in a circle, or a house when it has none.
private struct CommunityPicture: View {
    let url: URL?
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.1))
            Image(systemName: "house.fill").font(.system(size: size * 0.4)).foregroundStyle(.secondary)
            if let url {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A person in a list: picture, name, and small tags. Tap for their profile.
private struct PersonRow: View {
    let name: String
    let photoURL: URL?
    var detail: String? = nil
    var tags: [MemberTag] = []
    var trailing: AnyView? = nil
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Button(action: onOpen) {
                HStack(spacing: Spacing.m) {
                    Avatar(url: photoURL, name: name, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: name).sheetEntryStyle().lineLimit(2)
                        if let detail {
                            Text(verbatim: detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if !tags.isEmpty {
                            // Small rounded pills that wrap onto a second line if needed.
                            FlowLayout(spacing: 6) {
                                ForEach(tags, id: \.text) { tag in
                                    Stamp(text: tag.text, systemImage: tag.symbol, color: tag.color, small: true)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let trailing { trailing }
        }
        .sheetRow()
    }
}

// MARK: - Not in a community yet

private struct FindCommunityView: View {
    @Bindable var viewModel: CommunityViewModel
    @Environment(AuthStore.self) private var auth
    @State private var isCreating = false
    @State private var openCommunity: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SheetTitle(title: "Community", kicker: String(localized: "Find your neighborhood"))
            Text("Neighbors in the same community check on each other in an emergency, and share photos of what's going on. Search for yours, or start it if it's not here yet.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                TextField("Neighborhood name", text: $viewModel.query)
                    .font(.title3)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityIdentifier("communitySearch")
                if viewModel.isSearching { ProgressView() }
            }
            .padding(.horizontal, Spacing.l)
            .frame(minHeight: 54)
            .background(Color.paperRaised, in: Capsule())
            .onChange(of: viewModel.query) { viewModel.queryChanged() }

            CommunityList(viewModel: viewModel, title: "Neighborhoods", canJoin: true) { openCommunity = $0 }

            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionLabel("Not here yet?")
                Button { isCreating = true } label: {
                    Label("Start a community", systemImage: "plus")
                }
                .buttonStyle(InkButtonStyle(prominent: false))
                .accessibilityIdentifier("createCommunity")
                SheetNote(text: "You'll be its admin, so you approve who joins and which photos go in the Weekly Recap.",
                          systemImage: "star")
            }

            RespondersSection(viewModel: viewModel, city: nil)
        }
        .task { await viewModel.search() }
        .sheet(isPresented: $isCreating) {
            CreateCommunitySheet(viewModel: viewModel).sheetBrand()
        }
        .sheet(item: $openCommunity) { id in
            CommunityPageView(communityID: id, viewModel: viewModel).sheetBrand()
        }
    }
}

/// Neighborhoods from the search. Tap one to see its page and Weekly Recap.
private struct CommunityList: View {
    @Bindable var viewModel: CommunityViewModel
    let title: LocalizedStringKey
    let canJoin: Bool
    var excluding: Int? = nil
    let onOpen: (Int) -> Void
    @Environment(AuthStore.self) private var auth

    private var shown: [CommunitySummary] { viewModel.results.filter { $0.id != excluding } }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel(title)
            if shown.isEmpty && !viewModel.isSearching {
                Text(viewModel.query.trimmed.isEmpty ? "No communities yet." : "No community called \"\(viewModel.query.trimmed)\" yet.")
                    .font(.callout).foregroundStyle(.secondary)
                    .sheetBox(padding: Spacing.l)
            } else {
                SheetCard {
                    ForEach(shown) { community in
                        HStack(spacing: Spacing.m) {
                            Button { onOpen(community.id) } label: {
                                HStack(spacing: Spacing.m) {
                                    CommunityPicture(url: community.photoURL, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: community.name).sheetEntryStyle().lineLimit(1)
                                        Text("\(community.city) · \(memberCount(community.memberCount))")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("openCommunity_\(community.id)")
                            if canJoin {
                                Button("Ask to join") { Task { await viewModel.join(community, auth: auth) } }
                                    .buttonStyle(SmallInkButtonStyle())
                                    .disabled(viewModel.isWorking)
                                    .accessibilityIdentifier("join_\(community.id)")
                            }
                        }
                        .sheetRow()
                        .accessibilityElement(children: .contain)
                    }
                }
            }
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
                        .foregroundStyle(.secondary)
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }.flat()
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if await viewModel.create(name: name, city: city, auth: auth) { dismiss() }
                        }
                    }
                    .disabled(name.trimmed.count < 2 || city.trimmed.isEmpty || viewModel.isWorking)
                    .accessibilityIdentifier("confirmCreateCommunity")
                }
                .flat()
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
            VStack(alignment: .leading, spacing: Spacing.m) {
                Stamp(text: String(localized: "Waiting for approval"), systemImage: "hourglass", color: Color(.systemOrange))
                Text("Waiting to join \(community.name)")
                    .font(.sheetHeading)
                    .accessibilityIdentifier("pendingCommunity")
                Text("The community's admin will approve your request. Pull down to check again.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .sheetBox()
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
    @Bindable var viewModel: CommunityViewModel
    @Environment(AuthStore.self) private var auth
    @State private var confirmsLeaving = false
    @State private var openPerson: Int?
    @State private var openCommunity: Int?
    @State private var newPhoto: Data?
    @State private var isSavingAway = false
    @State private var showsConnections = false

    var body: some View {
        Group {
            switch viewModel.detail {
            case .loading:
                LoadingView()
            case .failed(let error):
                SheetMessage(error: error, action: { Task { await viewModel.loadDetail(id: communityID) } })
            case .loaded(let community):
                content(community)
            }
        }
        .task {
            await viewModel.loadDetail(id: communityID)
            await viewModel.loadResponders(city: auth.me?.community?.city)
            await viewModel.search()
        }
        .confirmationDialog("Leave this community?", isPresented: $confirmsLeaving, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await viewModel.leave(id: communityID, auth: auth) } }
        } message: {
            Text("You can ask to join again later.")
        }
        .sheet(item: $openPerson) { id in PersonProfileView(personID: id).sheetBrand() }
        .sheet(item: $openCommunity) { id in CommunityPageView(communityID: id, viewModel: viewModel).sheetBrand() }
        .sheet(item: Binding(get: { newPhoto.map(PickedJPEG.init) }, set: { newPhoto = $0?.data })) { picked in
            if case .loaded(let community) = viewModel.detail {
                AddRecapPhotoSheet(jpeg: picked.data, isAdmin: community.isAdmin) { caption in
                    await viewModel.addRecapPhoto(picked.data, caption: caption, in: community)
                }
                .sheetBrand()
            }
        }
        .fullScreenCover(isPresented: $showsConnections) {
            if case .loaded(let community) = viewModel.detail {
                ConnectionsView(members: community.members, pairs: community.buddyPairs).sheetBrand()
            }
        }
        .successOverlay(isPresented: $viewModel.photoSent,
                        text: viewModel.detail.value?.isAdmin == true ? "Added" : "Sent to the admin")
    }

    private func content(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            header(community)
            recap(community)
            if community.isAdmin && !community.pendingPhotos.isEmpty { pendingPhotos(community) }
            if community.isAdmin && !community.joinRequests.isEmpty { joinRequests(community) }
            awayToggle
            connectionsButton(community)
            members(community)
            RespondersSection(viewModel: viewModel, city: community.city) { openPerson = $0 }
            CommunityList(viewModel: viewModel, title: "Other communities", canJoin: false,
                          excluding: community.id) { openCommunity = $0 }
            Button("Leave community", role: .destructive) { confirmsLeaving = true }
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: minimumTapSize)
        }
    }

    private func header(_ community: CommunityDetail) -> some View {
        HStack(spacing: Spacing.m) {
            Group {
                if community.isAdmin {
                    PhotoChooser(onPicked: { jpeg in Task { await viewModel.setPhoto(jpeg, in: community) } }) {
                        CommunityPicture(url: community.photoURL, size: 64)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.paper)
                                    .frame(width: 24, height: 24)
                                    .background(Color.ink, in: Circle())
                            }
                    }
                    .accessibilityLabel("Change the community's picture")
                } else {
                    CommunityPicture(url: community.photoURL, size: 64)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: community.city.uppercased() + " · " + memberCount(community.memberCount).uppercased())
                    .font(.sheetLabel).tracking(1.1).foregroundStyle(.secondary)
                Text(verbatim: community.name).font(.sheetDisplay).lineLimit(2).minimumScaleFactor(0.6)
                if community.isAdmin {
                    Stamp(text: String(localized: "You're the admin"), systemImage: "star.fill")
                }
            }
        }
        .padding(.trailing, 52)   // room for the gear button
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("communityHeader")
    }

    private func recap(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                // The Weekly Recap's own heading, in Quitars.
                Text("Weekly recap")
                    .font(.recap(26, relativeTo: .title2))
                    .foregroundStyle(ThemeStore.shared.theme.labelColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.s)
                    .padding(.leading, Spacing.xs)
                    .accessibilityAddTraits(.isHeader)
                PhotoChooser(onPicked: { newPhoto = $0 }) {
                    Label("Add photo", systemImage: "plus")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, Spacing.m)
                        .frame(minHeight: 36)
                        .background(Color.paperRaised, in: Capsule())
                }
                .accessibilityIdentifier("addRecapPhoto")
            }
            RecapCarousel(photos: community.recap, isAdmin: community.isAdmin, canReact: true, onAction: { photo, action in
                Task {
                    switch action {
                    case .pin: await viewModel.change(photo, .pin, in: community)
                    case .unpin: await viewModel.change(photo, .unpin, in: community)
                    case .remove: await viewModel.remove(photo, in: community)
                    }
                }
            }, onReact: { photo, emoji in
                Task { await viewModel.react(photo, with: emoji, in: community) }
            })
            Text(community.isAdmin
                 ? "Photos stay for a week. Use ... on a photo to pin it so it stays."
                 : "Photos stay for a week. The admin approves new ones first.")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.leading, Spacing.xs)
        }
    }

    private func pendingPhotos(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel("Photos waiting for you")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.m) {
                    ForEach(community.pendingPhotos) { photo in
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            AsyncImage(url: photo.imageURL) { $0.resizable().scaledToFill() } placeholder: {
                                Color.primary.opacity(0.08)
                            }
                            .frame(width: 170, height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.paperCard, style: .continuous))
                            Text(verbatim: photo.caption.isEmpty ? photo.uploaderName : "\(photo.caption) · \(photo.uploaderName)")
                                .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: Spacing.s) {
                                Button("No") { Task { await viewModel.change(photo, .reject, in: community) } }
                                    .buttonStyle(SmallInkButtonStyle(prominent: false))
                                Button("Approve") { Task { await viewModel.change(photo, .approve, in: community) } }
                                    .buttonStyle(SmallInkButtonStyle())
                                    .accessibilityIdentifier("approvePhoto_\(photo.id)")
                            }
                        }
                        .frame(width: 170)
                        .padding(Spacing.m)
                        .paperCard()
                    }
                }
            }
        }
    }

    private func joinRequests(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel("Asking to join")
            SheetCard {
                ForEach(community.joinRequests) { person in
                    PersonRow(name: person.name, photoURL: person.photoURL, trailing: AnyView(
                        HStack(spacing: Spacing.s) {
                            Button("Decline") { Task { await viewModel.answer(person, approve: false, in: community) } }
                                .buttonStyle(SmallInkButtonStyle(prominent: false))
                            Button("Approve") { Task { await viewModel.answer(person, approve: true, in: community) } }
                                .buttonStyle(SmallInkButtonStyle())
                                .accessibilityIdentifier("approve_\(person.userId)")
                        }
                        .disabled(viewModel.isWorking)
                    )) {}
                }
            }
        }
    }

    /// A small, look-only preview of the connections web, and the button
    /// that opens the full one (where you can drag, tap and pop bubbles).
    private func connectionsButton(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel("Connections")
            VStack(spacing: 0) {
                ConnectionsWeb(members: community.members, pairs: community.buddyPairs,
                               interactive: false, bubbleSize: 44)
                    .frame(height: 210)
                    .clipped()
                    .accessibilityHidden(true)
                Button { showsConnections = true } label: {
                    HStack(spacing: Spacing.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("View connections").font(.headline)
                            Text("\(community.buddyPairs.count) buddy pairs · \(community.members.filter { !$0.hasBuddy }.count) without a buddy")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .padding(Spacing.l)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("seeConnections")
            }
            .paperCard()
            .clipShape(RoundedRectangle(cornerRadius: Radius.paperCard, style: .continuous))
        }
    }

    /// "I'm away from home": shows next to your name, so neighbors don't go
    /// looking for you at home during an emergency.
    private var awayToggle: some View {
        Toggle(isOn: Binding(
            get: { auth.me?.awayFromHome ?? false },
            set: { away in
                Task {
                    isSavingAway = true
                    defer { isSavingAway = false }
                    do throws(APIError) { try await auth.updateProfile(.init(awayFromHome: away)) }
                    catch { viewModel.actionError = error }
                    await viewModel.loadDetail(id: communityID)
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Label("I'm away from home", systemImage: "suitcase.fill").font(.headline)
                Text("Neighbors see \"Away from home\" next to your name, so nobody goes looking for you there.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color(.systemGreen))
        .disabled(isSavingAway)
        .sheetBox(padding: Spacing.l)
        .accessibilityIdentifier("awayFromHomeToggle")
    }

    /// Members, split by who has a buddy and who still needs one.
    private func members(_ community: CommunityDetail) -> some View {
        let needing = community.members.filter { !$0.hasBuddy }
        let covered = community.members.filter(\.hasBuddy)
        return VStack(alignment: .leading, spacing: Spacing.l) {
            memberGroup("No buddy yet", subtitle: "Volunteers can offer to check on them from Roll Call > I check on.",
                        needing, identifier: "membersWithoutBuddy")
            memberGroup("Has a buddy", subtitle: nil, covered, identifier: "membersWithBuddy")
        }
    }

    @ViewBuilder
    private func memberGroup(_ title: LocalizedStringKey, subtitle: LocalizedStringKey?, _ people: [CommunityMember],
                             identifier: String) -> some View {
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    SectionLabel(title)
                    Text("\(people.count)").font(.sheetLabel).foregroundStyle(.secondary).padding(.top, Spacing.s)
                }
                SheetCard {
                    ForEach(people) { person in
                        PersonRow(name: person.name, photoURL: person.photoURL, tags: tags(for: person)) {
                            openPerson = person.userId
                        }
                        .accessibilityIdentifier("member_\(person.userId)")
                    }
                }
                if let subtitle, people.contains(where: \.wantsBuddy) {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).padding(.leading, Spacing.xs)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
        }
    }

    private func tags(for person: CommunityMember) -> [MemberTag] {
        var tags: [MemberTag] = []
        if person.isAdmin { tags.append(MemberTag(text: String(localized: "Admin"), symbol: "star.fill", color: .secondary)) }
        if person.awayFromHome {
            tags.append(MemberTag(text: String(localized: "Away from home"), symbol: "suitcase.fill", color: Color(.systemOrange)))
        }
        if person.wantsBuddy {
            tags.append(MemberTag(text: String(localized: "Looking for a buddy"), symbol: "magnifyingglass", color: Color(.systemOrange)))
        }
        if person.checksOn > 0 {
            tags.append(MemberTag(text: String(localized: "Checks on \(person.checksOn)"), symbol: "hand.raised.fill",
                                  color: Color(.systemTeal)))
        } else if person.isVolunteer {
            tags.append(MemberTag(text: String(localized: "Ready to help"), symbol: "hand.raised", color: .secondary))
        }
        return tags
    }
}

/// First responders who serve this town. Anyone can see them, so residents
/// know who's helping and can report misuse.
private struct RespondersSection: View {
    let viewModel: CommunityViewModel
    let city: String?
    var onOpen: ((Int) -> Void)? = nil
    @State private var openPerson: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel(city.map { "First responders in \($0)" } ?? "First responders")
            if viewModel.responders.isEmpty {
                Text("No verified first responders here yet.")
                    .font(.callout).foregroundStyle(.secondary)
                    .sheetBox(padding: Spacing.l)
            } else {
                SheetCard {
                    ForEach(viewModel.responders) { person in
                        PersonRow(name: person.name, photoURL: person.photoURL,
                                  detail: person.responder.map { "\($0.role), \($0.agency)" },
                                  tags: [MemberTag(text: String(localized: "Verified"), symbol: "checkmark.seal.fill", color: Color(.systemBlue))]) {
                            if let onOpen { onOpen(person.id) } else { openPerson = person.id }
                        }
                        .accessibilityIdentifier("responder_\(person.id)")
                    }
                }
            }
        }
        .task { if onOpen == nil { await viewModel.loadResponders(city: city) } }
        .sheet(item: $openPerson) { id in PersonProfileView(personID: id).sheetBrand() }
    }
}

// MARK: - Another community's page

/// Any community's page: its picture, its Weekly Recap, and "Ask to join"
/// if you're not in one yet.
struct CommunityPageView: View {
    let communityID: Int
    let viewModel: CommunityViewModel
    @State private var state: LoadState<CommunityDetail> = .loading
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    switch state {
                    case .loading: LoadingView()
                    case .failed(let error): SheetMessage(error: error, action: { Task { await load() } })
                    case .loaded(let community): content(community)
                    }
                }
                .padding(Spacing.l)
            }
            .sheetPage()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }.flat()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do { state = .loaded(try await APIClient.shared.fetchCommunity(id: communityID)) }
        catch { state = .failed(error) }
    }

    private func content(_ community: CommunityDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(spacing: Spacing.m) {
                CommunityPicture(url: community.photoURL, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: community.city.uppercased() + " · " + memberCount(community.memberCount).uppercased())
                        .font(.sheetLabel).tracking(1.1).foregroundStyle(.secondary)
                    Text(verbatim: community.name).font(.sheetDisplay).lineLimit(2).minimumScaleFactor(0.6)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("communityPageHeader")
            SectionLabel("Weekly recap")
            RecapCarousel(photos: community.recap)
            if auth.me?.community == nil && community.myStatus == nil {
                Button("Ask to join") {
                    Task {
                        await viewModel.join(CommunitySummary(id: community.id, name: community.name, city: community.city,
                                                              photoUrl: community.photoUrl, memberCount: community.memberCount,
                                                              myStatus: nil, isAdmin: false), auth: auth)
                        dismiss()
                    }
                }
                .buttonStyle(InkButtonStyle())
            }
        }
    }
}

/// Add a caption to a new Weekly Recap photo, then send it to the admin.
private struct AddRecapPhotoSheet: View {
    let jpeg: Data
    /// The admin's own photos go straight into the recap.
    let isAdmin: Bool
    let send: (String) async -> Void
    @State private var caption = ""
    @State private var isSending = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let image = UIImage(data: jpeg) {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(height: 320).frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.paperCard, style: .continuous))
                    }
                    LabeledField(label: "Caption (optional)", prompt: "What's happening?", text: $caption,
                                 handwritten: false, identifier: "recapCaption")
                    if isAdmin {
                        SheetNote(text: "It goes straight into the Weekly Recap for a week. Press and hold it there to pin it.",
                                  systemImage: "photo.stack")
                    } else {
                        SheetNote(text: "The admin sees it first. Once approved, everyone can see it for a week.",
                                  systemImage: "checkmark.shield")
                    }
                    Button {
                        Task {
                            isSending = true
                            await send(caption)
                            isSending = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            if isSending { ProgressView().tint(Color.paper) }
                            Text(isAdmin ? "Add to the Weekly Recap" : "Send to the admin")
                        }
                    }
                    .buttonStyle(InkButtonStyle())
                    .disabled(isSending)
                    .accessibilityIdentifier("sendRecapPhoto")
                }
                .padding(Spacing.l)
            }
            .sheetPage()
            .navigationTitle("New photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }.flat()
            }
        }
    }
}

/// Lets a picked photo open a sheet (sheets need an Identifiable item).
private struct PickedJPEG: Identifiable {
    let data: Data
    var id: Int { data.hashValue }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

/// One small pill under a member's name: "Admin", "Away from home", "Checks on 2".
struct MemberTag {
    let text: String
    let symbol: String
    let color: Color
}
