//
//  ResidentHomeView.swift
//  RollCall
//
//  The "My household" part of the Roll Call tab, laid out like the resident's
//  entry on a roll-call sheet: their number and name, any buddy offers to
//  answer, a calm "no emergencies" note, then their home, needs, buddy and
//  privacy, each on its own paper card. What the resident wrote in (their
//  name, address, buddy's name) is shown in handwriting.
//  (During an emergency this is where the roll call appears; that's step 3.)
//

import MapKit
import SwiftUI

struct ResidentHomeView: View {
    @Environment(AuthStore.self) private var auth
    @State private var viewModel: ResidentHomeViewModel
    @State private var isEditing = false
    @State private var endingMatchWith: Buddy?
    @State private var openPerson: Int?
    @State private var buddyNeedsHelp: Buddy?
    @State private var checkedIn = false
    @Environment(\.openURL) private var openURL

    init(householdID: Int) {
        _viewModel = State(initialValue: ResidentHomeViewModel(householdID: householdID))
    }

    var body: some View {
        content
            .task { await viewModel.load() }
            .fullScreenCover(isPresented: $isEditing) {
                if let household = viewModel.household {
                    ProfileWizardView(mode: .edit(householdID: household.id), existing: household) { saved in
                        viewModel.replace(with: saved)
                    }
                    .sheetBrand()
                }
            }
            .alert("Couldn't do that", isPresented: Binding(
                get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.actionError?.message ?? "")
            }
            .sheet(item: $openPerson) { id in PersonProfileView(personID: id).sheetBrand() }
            .successOverlay(isPresented: $checkedIn, text: "Sent to your buddy")
            .animation(.snappy, value: AlertsManager.shared.answeredThisVisit)
            .fullScreenCover(item: $buddyNeedsHelp) { buddy in
                EmergencyHelpView(name: buddy.name, address: nil, facts: [], emergencyContact: nil).sheetBrand()
            }
            .confirmationDialog("End your buddy match?", isPresented: Binding(
                get: { endingMatchWith != nil }, set: { if !$0 { endingMatchWith = nil } }
            ), titleVisibility: .visible, presenting: endingMatchWith) { buddy in
                Button("End match with \(buddy.name)", role: .destructive) { Task { await viewModel.removeBuddy(buddy) } }
            } message: { _ in
                Text("They'll no longer see your household or be asked to check on you.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingView(text: "Loading your household…")
        case .failed(.notFound):
            // The household no longer exists (for example, the demo data was reset).
            SheetMessage("This household no longer exists", message: "It may have been deleted, or the demo data was reset.",
                         systemImage: "house.slash", actionTitle: "Refresh", action: { Task { await auth.refresh() } })
        case .failed(let error):
            SheetMessage(error: error, action: { Task { await viewModel.retry() } })
        case .loaded(let household):
            VStack(alignment: .leading, spacing: Spacing.l) {
                entryHeader(household)
                ForEach(viewModel.buddyRequests) { request in
                    buddyRequestBox(request)
                }
                // Hidden once answered, until the next time the app is opened.
                if !AlertsManager.shared.answeredThisVisit {
                    checkInCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                homeSection(household)
                needsSection(household)
                buddySection(household)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionLabel("Privacy")
                    SheetCard {
                    NavigationLink {
                        PrivacyView(household: household, isDeleting: viewModel.isDeleting,
                                    onDelete: { await viewModel.deleteMyData() },
                                    onDeleted: { await auth.refresh() })
                        .sheetBrand()
                    } label: {
                        linkRow(title: "Your privacy", subtitle: "Who can see your information, and deleting it")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacyLink")
                    }
                }
            }
        }
    }

    /// "No. 014" and the resident's name written on the line, like their
    /// entry on a roll call, with a green stamp showing they're on it.
    private func entryHeader(_ household: Household) -> some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "No. \(String(format: "%03d", household.id))").sheetLabelStyle().foregroundStyle(.secondary)
                Text(verbatim: household.displayName)
                    .sheetEntryStyle(large: true)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Spacing.m)   // room under the hanging tag
        .sheetBox()
        // "On the roll call" hangs from the top edge of the card.
        .hangingTag(Stamp(text: String(localized: "On the roll call"), systemImage: "checkmark", color: Color(.systemGreen)))
        .accessibilityElement(children: .combine)
    }

    /// "How are you?": a small card. One tap tells your buddy you're safe, or
    /// that you need help. (The same buttons are on the danger notification
    /// and the Lock Screen.) It hides after an answer, until the app is opened again.
    private var checkInCard: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s) {
                checkInTitle
                Spacer(minLength: Spacing.s)
                checkInButtons
            }
            VStack(alignment: .leading, spacing: Spacing.s) {   // very large text
                checkInTitle
                checkInButtons
            }
        }
        .sheetBox(padding: Spacing.m)
        .disabled(viewModel.isCheckingIn)
        .accessibilityElement(children: .contain)
    }

    private var checkInTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How are you?").font(.heading(19, relativeTo: .headline))
            Text("Tells your buddy").font(.app(.footnote)).foregroundStyle(.secondary)
        }
    }

    private var checkInButtons: some View {
        HStack(spacing: Spacing.s) {
            checkInButton("I'm safe", "checkmark", Color(.systemGreen), safe: true)
                .accessibilityIdentifier("checkInSafe")
            checkInButton("Need help", "exclamationmark.triangle.fill", Color(.systemRed), safe: false)
                .accessibilityIdentifier("checkInHelp")
        }
    }

    private func checkInButton(_ title: LocalizedStringKey, _ symbol: String, _ color: Color, safe: Bool) -> some View {
        Button {
            Task {
                if await viewModel.checkIn(safe: safe) {
                    checkedIn = true
                }
            }
        } label: {
            Label(title, systemImage: symbol)
                .font(.app(.callout).weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: minimumTapSize)
                .foregroundStyle(.white)
                .background(color, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(safe ? Text("I'm safe") : Text("I need help"))
    }

    /// "Daniel offered to check on you": the resident decides.
    private func buddyRequestBox(_ request: BuddyRequestToMe) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Buddy offer").sheetLabelStyle().foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: request.volunteerName).sheetEntryStyle(large: true)
                Text("offered to check on you").font(.sheetHeading)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(request.sameCommunity
                 ? String(localized: "A volunteer from your community.")
                 : String(localized: "A volunteer from \(request.volunteerCity). They're not in your community."))
                .font(.app(.body))
                .fixedSize(horizontal: false, vertical: true)
            Text("If you accept, they'll see your name, address, phone and needs, and check on you if you don't answer during an emergency.")
                .font(.app(.callout)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.m) {
                Button("Not now") { Task { await viewModel.answer(request, accept: false) } }
                    .buttonStyle(InkButtonStyle(prominent: false))
                    .accessibilityIdentifier("declineBuddy")
                Button("Accept") { Task { await viewModel.answer(request, accept: true) } }
                    .buttonStyle(InkButtonStyle())
                    .accessibilityIdentifier("acceptBuddy")
            }
            .disabled(viewModel.isAnswering)
        }
        .sheetBox(emphasis: true)
        .accessibilityElement(children: .contain)
    }

    private func homeSection(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel("Home")
            VStack(alignment: .leading, spacing: Spacing.m) {
            Map(initialPosition: .region(MKCoordinateRegion(center: household.coordinate,
                                                            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))),
                interactionModes: []) {
                Marker(household.address, systemImage: "house.fill", coordinate: household.coordinate)
                    .tint(Color.ink)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: household.address).sheetEntryStyle()
                    Text(verbatim: "\(household.city), TX \(household.zipCode)").sheetEntryStyle()
                }
                Spacer()
                Button("Edit") { isEditing = true }
                    .buttonStyle(SmallInkButtonStyle(prominent: false))
                    .accessibilityLabel("Edit household")
                    .accessibilityIdentifier("editHousehold")
            }
            }
            .sheetBox()
        }
    }

    private func needsSection(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel("Who lives here, and needs")
            TagChips(tags: household.tags).sheetBox()
        }
    }

    @ViewBuilder
    /// The neighbors who check on you. You can have more than one.
    private func buddySection(_ household: Household) -> some View {
        let buddies = household.allBuddies
        return VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel(buddies.count > 1 ? "Your buddies" : "Buddy")
            SheetCard {
                if buddies.isEmpty {
                    if household.wantsBuddy {
                        textRow(title: "Waiting for a buddy",
                                subtitle: "Neighbors in your community can offer to check on you. You'll choose whether to accept.")
                    } else {
                        Button { isEditing = true } label: {
                            linkRow(title: "Want a neighbor to check on you?", subtitle: "Ask for a volunteer buddy in your profile.")
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ForEach(buddies) { buddyRow($0) }
                }
            }
            if !buddies.isEmpty {
                Text("More neighbors can offer to check on you too. Each one shows up here once you accept.")
                    .font(.app(.footnote)).foregroundStyle(.secondary)
                    .padding(.leading, Spacing.xs)
            }
        }
    }

    private func buddyRow(_ buddy: Buddy) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                Button { openPerson = buddy.userId } label: {
                    HStack(spacing: Spacing.m) {
                        Avatar(url: nil, name: buddy.name, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: buddy.name).sheetEntryStyle()
                            Text("Checks on you if you don't answer during an emergency.")
                                .font(.app(.callout)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens their profile")
                Spacer(minLength: 0)
                Menu {
                    Button("End buddy match", systemImage: "person.badge.minus", role: .destructive) {
                        endingMatchWith = buddy
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.app(.title3).weight(.bold))
                        .frame(width: minimumTapSize, height: minimumTapSize)
                }
                .accessibilityLabel("Options for \(buddy.name)")
            }
            // Call and Text side by side, "They need help" on its own line,
            // so the row never gets wider than the phone.
            if let digits = PersonProfileView.digits(buddy.phone) {
                HStack(spacing: Spacing.s) {
                    Button { open("tel:\(digits)") } label: { Label("Call", systemImage: "phone.fill") }
                        .buttonStyle(InkButtonStyle())
                        .accessibilityIdentifier("callBuddy")
                    Button { open("sms:\(digits)") } label: { Label("Text", systemImage: "message.fill") }
                        .buttonStyle(InkButtonStyle(prominent: false))
                        .accessibilityIdentifier("textBuddy")
                }
            }
            Button { buddyNeedsHelp = buddy } label: {
                Label("They need help", systemImage: "cross.case.fill")
            }
            .buttonStyle(InkButtonStyle(prominent: false, destructive: true))
            .accessibilityIdentifier("buddyNeedsHelp")
        }
        .sheetRow()
        .accessibilityElement(children: .contain)
    }

    private func open(_ link: String) {
        if let url = URL(string: link) { openURL(url) }
    }

    private func textRow(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sheetHeading)
            Text(subtitle).font(.app(.callout)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheetRow()
        .accessibilityElement(children: .combine)
    }

    private func linkRow(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sheetHeading)
                Text(subtitle).font(.app(.callout)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right").font(.app(.headline)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .sheetRow()
        .accessibilityElement(children: .combine)
    }
}
