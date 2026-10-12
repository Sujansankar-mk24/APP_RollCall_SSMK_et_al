//
//  ResidentHomeView.swift
//  RollCall
//
//  The "My household" part of the Roll Call tab: a calm "all clear" when
//  nothing is happening, volunteers asking to be their buddy, their household
//  at a glance, their buddy, and their privacy.
//  (During an emergency this is where the roll call appears; that's step 3.)
//

import MapKit
import SwiftUI

struct ResidentHomeView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.brand) private var brand
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
                    .rollCallBrand()
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
            MessageCard(systemImage: "house.slash", title: "This household no longer exists",
                        message: "It may have been deleted, or the demo data was reset.",
                        actionTitle: "Refresh", action: { Task { await auth.refresh() } })
        case .failed(let error):
            MessageCard(error: error, action: { Task { await viewModel.retry() } })
        case .loaded(let household):
            VStack(alignment: .leading, spacing: Spacing.l) {
                greeting(household)
                ForEach(viewModel.buddyRequests) { request in
                    buddyRequestCard(request)
                }
                allClearCard
                householdCard(household)
                buddyCard(household)
                NavigationLink {
                    PrivacyView(household: household, isDeleting: viewModel.isDeleting,
                                onDelete: { await viewModel.deleteMyData() },
                                onDeleted: { await auth.refresh() })
                    .rollCallBrand()
                } label: {
                    rowCard(symbol: "lock.shield.fill", title: "Your privacy",
                            subtitle: "Who can see your information, and deleting it")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("privacyLink")
                EmergencyBanner()
            }
        }
    }

    /// "Daniel wants to check on you": the resident decides.
    private func buddyRequestCard(_ request: BuddyRequestToMe) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Text(initials(request.volunteerName))
                    .font(.headline).fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(brand, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(request.volunteerName) offered to check on you")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(request.sameCommunity
                         ? String(localized: "A volunteer from your community.")
                         : String(localized: "A volunteer from \(request.volunteerCity). They're not in your community."))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("If you accept, they'll see your name, address, phone and needs, and check on you if you don't answer during an emergency.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.m) {
                Button("Not now") { Task { await viewModel.answer(request, accept: false) } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("declineBuddy")
                Button("Accept") { Task { await viewModel.answer(request, accept: true) } }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("acceptBuddy")
            }
            .controlSize(.large)
            .disabled(viewModel.isAnswering)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(brand.opacity(0.5), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
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
                .foregroundStyle(brand)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("No emergencies near you").font(.headline)
                Text("If one starts, RollCall will ask if you're safe. Answering takes one tap.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brand.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func householdCard(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: .region(MKCoordinateRegion(center: household.coordinate,
                                                            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))),
                interactionModes: []) {
                Marker(household.address, systemImage: "house.fill", coordinate: household.coordinate)
                    .tint(brand)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 130)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(household.address).font(.headline)
                        Text("\(household.city) \(household.zipCode)").font(.subheadline).foregroundStyle(.secondary)
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
                    .background(brand, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your buddy").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Text(buddy.name).font(.headline)
                    Text("Checks on you if you don't answer during an emergency.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Menu {
                    Button("End buddy match", systemImage: "person.badge.minus", role: .destructive) {
                        confirmsEndingMatch = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: minimumTapSize, height: minimumTapSize)
                }
                .accessibilityLabel("Buddy options")
            }
            .card()
            .accessibilityElement(children: .contain)
        } else if household.wantsBuddy {
            rowCard(symbol: "person.2.wave.2.fill", title: "Waiting for a buddy",
                    subtitle: "Volunteers in your community can offer to check on you. You'll choose whether to accept.")
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
                .foregroundStyle(brand)
                .frame(width: 44, height: 44)
                .background(brand.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
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
}
