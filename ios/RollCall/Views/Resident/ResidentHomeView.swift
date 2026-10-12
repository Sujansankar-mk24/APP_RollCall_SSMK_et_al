//
//  ResidentHomeView.swift
//  RollCall
//
//  A resident's home screen: a calm "all clear" when nothing is happening,
//  their household at a glance, their volunteer buddy, and their privacy.
//  (During an emergency this is where the roll call appears; that's step 3.)
//

import MapKit
import SwiftUI

struct ResidentHomeView: View {
    @Environment(AppSession.self) private var session
    @State private var viewModel: ResidentHomeViewModel
    @State private var isEditing = false

    init(householdID: Int) {
        _viewModel = State(initialValue: ResidentHomeViewModel(householdID: householdID))
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        RoleButton(name: viewModel.household?.firstName ?? String(localized: "Resident"))
                    }
                    ToolbarItem(placement: .topBarTrailing) { AppearanceToolbarMenu() }
                }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .fullScreenCover(isPresented: $isEditing) {
            if let household = viewModel.household {
                ProfileWizardView(mode: .edit(householdID: household.id), existing: household,
                                  viewer: Viewer(role: .resident, id: household.id)) { saved in
                    viewModel.replace(with: saved)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading your household…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(.notFound):
            // The household no longer exists (deleted, or the demo was reset).
            MessageCard(systemImage: "house.slash", title: "This household no longer exists",
                        message: "It may have been deleted, or the demo data was reset.",
                        actionTitle: "Choose again", action: { session.switchRole() })
                .padding(Spacing.l).frame(maxHeight: .infinity)
        case .failed(let error):
            MessageCard(error: error, action: { Task { await viewModel.retry() } })
                .padding(Spacing.l).frame(maxHeight: .infinity)
        case .loaded(let household):
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    greeting(household)
                    allClearCard
                    householdCard(household)
                    buddyCard(household)
                    NavigationLink {
                        PrivacyView(household: household, isDeleting: viewModel.isDeleting) {
                            if await viewModel.deleteMyData() { session.switchRole() }
                        }
                    } label: {
                        rowCard(symbol: "lock.shield.fill", title: "Your privacy",
                                subtitle: "Who can see your information, and deleting it")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacyLink")
                    EmergencyBanner()
                }
                .padding(Spacing.l)
            }
        }
    }

    private func greeting(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Hi, \(household.firstName)")
                .font(.largeTitle.weight(.bold))
                .fontDesign(.rounded)
            Label("You're on the roll call", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.systemGreen))
        }
        .accessibilityElement(children: .combine)
    }

    /// The calm "nothing is happening" state. Green and quiet on purpose.
    private var allClearCard: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("No emergencies near you").font(.headline)
                Text("If one starts, RollCall will ask if you're safe. Answering takes one tap.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func householdCard(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: .region(MKCoordinateRegion(center: household.coordinate,
                                                            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))),
                interactionModes: []) {
                Marker(household.address, systemImage: "house.fill", coordinate: household.coordinate)
                    .tint(Color.accentColor)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 130)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(household.address).font(.headline)
                        Text(household.city).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit") { isEditing = true }
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: minimumTapSize, minHeight: minimumTapSize)
                        .accessibilityLabel("Edit household")
                        .accessibilityIdentifier("editHousehold")
                }
                TagChips(tags: household.tags)
            }
            .padding(Spacing.l)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    @ViewBuilder
    private func buddyCard(_ household: Household) -> some View {
        if let buddy = household.buddy {
            HStack(spacing: Spacing.m) {
                Text(initials(buddy.name))
                    .font(.headline).fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color(.systemTeal), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your buddy").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Text(buddy.name).font(.headline)
                    Text("Checks on you if you don't answer during an emergency.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
            .accessibilityElement(children: .combine)
        } else if household.wantsBuddy {
            rowCard(symbol: "person.2.wave.2.fill", title: "Finding you a buddy",
                    subtitle: "We'll match you with a volunteer nearby.")
        } else {
            Button { isEditing = true } label: {
                rowCard(symbol: "person.2.wave.2.fill", title: "Want a neighbor to check on you?",
                        subtitle: "Ask for a volunteer buddy in your profile.")
            }
            .buttonStyle(.plain)
        }
    }

    private func rowCard(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
        }
        .card()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}
