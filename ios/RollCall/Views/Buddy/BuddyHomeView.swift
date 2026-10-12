//
//  BuddyHomeView.swift
//  RollCall
//
//  A volunteer buddy's home: the neighbors who asked them to check on them.
//  (Check-in statuses, calling and "I checked on them" arrive in step 6.)
//

import SwiftUI

struct BuddyHomeView: View {
    @State private var viewModel: BuddyHomeViewModel
    @State private var identities = DemoIdentitiesViewModel()

    init(volunteerID: Int) {
        _viewModel = State(initialValue: BuddyHomeViewModel(volunteerID: volunteerID))
    }

    private var myName: String {
        identities.state.value?.volunteers.first { $0.id == viewModel.volunteerID }?.name ?? String(localized: "Buddy")
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { RoleButton(name: myName) }
                    ToolbarItem(placement: .topBarTrailing) { AppearanceToolbarMenu() }
                }
        }
        .task {
            await identities.load()
            await viewModel.load()
        }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading your neighbors…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            MessageCard(error: error, action: { Task { await viewModel.retry() } })
                .padding(Spacing.l).frame(maxHeight: .infinity)
        case .loaded(let residents):
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Your neighbors")
                            .font(.largeTitle.weight(.bold)).fontDesign(.rounded)
                        Text("People who asked you to check on them in an emergency. Only you can see this list.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if residents.isEmpty {
                        MessageCard(systemImage: "person.2.wave.2", title: "No one assigned yet",
                                    message: "When a nearby resident asks for a buddy, they'll show up here.")
                    } else {
                        ForEach(residents) { resident in
                            residentCard(resident)
                        }
                    }
                }
                .padding(Spacing.l)
            }
        }
    }

    private func residentCard(_ resident: Household) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(resident.contactName).font(.headline)
                Spacer()
                if resident.language == .es {
                    Text("Español").font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }
            }
            Label("\(resident.address), \(resident.city)", systemImage: "mappin")
                .font(.subheadline).foregroundStyle(.secondary)
            TagChips(tags: resident.tags)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
