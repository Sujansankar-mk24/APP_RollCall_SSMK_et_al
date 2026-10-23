//
//  ResidentHomeView.swift
//  RollCall
//
//  The "My household" part of the Roll Call tab, laid out like the resident's
//  entry on a roll-call sheet: their number and name, any buddy offers to
//  answer, a calm "no emergencies" note, then their home, needs, buddy and
//  privacy as ruled sections.
//  (During an emergency this is where the roll call appears; that's step 3.)
//

import MapKit
import SwiftUI

struct ResidentHomeView: View {
    @Environment(AuthStore.self) private var auth
    @State private var viewModel: ResidentHomeViewModel
    @State private var isEditing = false
    @State private var confirmsEndingMatch = false

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
            .confirmationDialog("End your buddy match?", isPresented: $confirmsEndingMatch, titleVisibility: .visible) {
                Button("End match", role: .destructive) { Task { await viewModel.removeBuddy() } }
            } message: {
                Text("They'll no longer see your household or be asked to check on you.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading your household…").frame(maxWidth: .infinity, minHeight: 240)
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
                SheetNote(text: "No emergencies near you. If one starts, RollCall will ask if you're safe. Answering takes one tap.",
                          systemImage: "shield.lefthalf.filled")
                homeSection(household)
                needsSection(household)
                buddySection(household)
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Privacy")
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

    /// "No. 014" and the resident's name, like their line on the roll call,
    /// with a green stamp showing they're on it.
    private func entryHeader(_ household: Household) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "No. \(String(format: "%03d", household.id))").sheetLabelStyle().foregroundStyle(.secondary)
                Text("Hi, \(household.firstName)")
                    .font(.sheetHeading)
            }
            Spacer()
            Stamp(text: String(localized: "On the roll call"), systemImage: "checkmark", color: Color(.systemGreen))
        }
        .accessibilityElement(children: .combine)
    }

    /// "Daniel offered to check on you": the resident decides.
    private func buddyRequestBox(_ request: BuddyRequestToMe) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Buddy offer").sheetLabelStyle().foregroundStyle(.secondary)
            Text("\(request.volunteerName) offered to check on you")
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(request.sameCommunity
                 ? String(localized: "A volunteer from your community.")
                 : String(localized: "A volunteer from \(request.volunteerCity). They're not in your community."))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text("If you accept, they'll see your name, address, phone and needs, and check on you if you don't answer during an emergency.")
                .font(.callout).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionLabel("Home")
            Map(initialPosition: .region(MKCoordinateRegion(center: household.coordinate,
                                                            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))),
                interactionModes: []) {
                Marker(household.address, systemImage: "house.fill", coordinate: household.coordinate)
                    .tint(Color.ink)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 150)
            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1.5))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(household.address).font(.title3.weight(.semibold))
                    Text("\(household.city), TX \(household.zipCode)").font(.body).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit") { isEditing = true }
                    .buttonStyle(SmallInkButtonStyle(prominent: false))
                    .accessibilityLabel("Edit household")
                    .accessibilityIdentifier("editHousehold")
            }
        }
    }

    private func needsSection(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionLabel("Who lives here, and needs")
            TagChips(tags: household.tags)
        }
    }

    @ViewBuilder
    private func buddySection(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Buddy")
            if let buddy = household.buddy {
                HStack(spacing: Spacing.m) {
                    Text(initials(buddy.name))
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color.paper)
                        .frame(width: 48, height: 48)
                        .background(Color.ink)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your buddy").sheetLabelStyle().foregroundStyle(.secondary)
                        Text(buddy.name).font(.title3.weight(.semibold))
                        Text("Checks on you if you don't answer during an emergency.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button("End buddy match", systemImage: "person.badge.minus", role: .destructive) {
                            confirmsEndingMatch = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3.weight(.bold))
                            .frame(width: minimumTapSize, height: minimumTapSize)
                    }
                    .accessibilityLabel("Buddy options")
                }
                .sheetRow()
                .accessibilityElement(children: .contain)
            } else if household.wantsBuddy {
                textRow(title: "Waiting for a buddy",
                        subtitle: "Volunteers in your community can offer to check on you. You'll choose whether to accept.")
            } else {
                Button { isEditing = true } label: {
                    linkRow(title: "Want a neighbor to check on you?", subtitle: "Ask for a volunteer buddy in your profile.")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func textRow(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheetRow()
        .accessibilityElement(children: .combine)
    }

    private func linkRow(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right").font(.headline).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .sheetRow()
        .accessibilityElement(children: .combine)
    }
}
