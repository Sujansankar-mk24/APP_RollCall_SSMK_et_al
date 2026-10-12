//
//  WelcomeView.swift
//  RollCall
//
//  The first screen of the Roll Call tab: what a roll call is, and who you are.
//
//  This is a demo with no real accounts: you pick a role, and for a resident
//  or buddy you also pick which (fictional) person to act as, or register a
//  new household.
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppSession.self) private var session
    @State private var path: [Role] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    hero
                    VStack(spacing: Spacing.m) {
                        ForEach(Role.allCases) { role in
                            roleCard(role)
                        }
                    }
                    footer
                }
                .padding(Spacing.l)
            }
            .background(Color(.systemGroupedBackground))
            .navigationDestination(for: Role.self) { role in
                switch role {
                case .resident: ResidentStartView()
                case .buddy: VolunteerPickerView()
                case .responder: EmptyView()
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: Spacing.m) {
            BrandMark(size: 72)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.s)
            Text("Roll Call")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("When an emergency hits, everyone who signed up is asked if they're safe. Neighbors and responders see who still needs help, so no one gets left behind.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func roleCard(_ role: Role) -> some View {
        Button {
            if role == .responder {
                session.becomeResponder()
            } else {
                path.append(role)
            }
        } label: {
            HStack(spacing: Spacing.m) {
                Image(systemName: role.symbol)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(role.iAm)
                        .font(.headline)
                        .fontDesign(.rounded)
                    Text(role.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .card(padding: Spacing.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("role_\(role.rawValue)")
    }

    private var footer: some View {
        VStack(spacing: Spacing.s) {
            Label("Demo mode: every person and address is fictional.", systemImage: "theatermasks.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Text("In a life-threatening emergency, call 911.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.systemRed))
        }
        .multilineTextAlignment(.center)
        .padding(.bottom, Spacing.l)
    }
}

/// Resident: register a new household, or act as one of the demo households.
struct ResidentStartView: View {
    @Environment(AppSession.self) private var session
    @State private var identities = DemoIdentitiesViewModel()
    @State private var isRegistering = false

    var body: some View {
        List {
            Section {
                Button { isRegistering = true } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Register my household").font(.headline)
                            Text("About 2 minutes. You can change or delete it anytime.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
                    }
                    .padding(.vertical, Spacing.xs)
                }
                .accessibilityIdentifier("registerHousehold")
            }

            Section {
                switch identities.state {
                case .loading:
                    HStack { ProgressView(); Text("Loading demo households…").foregroundStyle(.secondary) }
                case .failed(let error):
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text(error.title).font(.headline)
                        Text(error.message).font(.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { Task { await identities.load() } }
                    }
                case .loaded(let all):
                    ForEach(groupedByTown(all.households), id: \.town) { group in
                        DisclosureGroup {
                            ForEach(group.entries) { entry in
                                Button {
                                    session.becomeResident(householdID: entry.id)
                                } label: {
                                    Text(entry.contactName).foregroundStyle(.primary)
                                }
                                .accessibilityIdentifier("household_\(entry.id)")
                            }
                        } label: {
                            Label("\(group.town)  (\(group.entries.count))", systemImage: "mappin")
                        }
                    }
                }
            } header: {
                Text("Or act as a demo household")
            } footer: {
                Text("These households are fictional. They exist so the demo works without real people.")
            }
        }
        .navigationTitle("Resident")
        .task { await identities.load() }
        .fullScreenCover(isPresented: $isRegistering) {
            ProfileWizardView(mode: .register, existing: nil) { household in
                session.becomeResident(householdID: household.id)
            }
        }
    }

    private func groupedByTown(_ entries: [DemoIdentities.HouseholdEntry]) -> [(town: String, entries: [DemoIdentities.HouseholdEntry])] {
        Dictionary(grouping: entries, by: \.city)
            .map { (town: $0.key, entries: $0.value) }
            .sorted { $0.town < $1.town }
    }
}

/// Buddy: pick which (fictional) volunteer to act as.
struct VolunteerPickerView: View {
    @Environment(AppSession.self) private var session
    @State private var identities = DemoIdentitiesViewModel()

    var body: some View {
        List {
            switch identities.state {
            case .loading:
                HStack { ProgressView(); Text("Loading volunteers…").foregroundStyle(.secondary) }
            case .failed(let error):
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(error.title).font(.headline)
                    Text(error.message).font(.subheadline).foregroundStyle(.secondary)
                    Button("Try again") { Task { await identities.load() } }
                }
            case .loaded(let all):
                Section {
                    ForEach(all.volunteers) { volunteer in
                        Button { session.becomeBuddy(volunteerID: volunteer.id) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(volunteer.name).font(.headline).foregroundStyle(.primary)
                                    Text(volunteer.city).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(volunteer.assigned == 1 ? "1 neighbor" : "\(volunteer.assigned) neighbors")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(minHeight: minimumTapSize)
                        }
                        .accessibilityIdentifier("volunteer_\(volunteer.id)")
                    }
                } footer: {
                    Text("These volunteers are fictional. Each one checks on the neighbors who asked for a buddy.")
                }
            }
        }
        .navigationTitle("Volunteer buddy")
        .task { await identities.load() }
    }
}

#Preview {
    WelcomeView().environment(AppSession())
}
