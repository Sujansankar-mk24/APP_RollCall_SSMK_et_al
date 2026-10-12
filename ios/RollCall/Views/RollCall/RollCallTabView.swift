//
//  RollCallTabView.swift
//  RollCall
//
//  The Roll Call tab (purple). Responders see their view. Everyone else
//  switches between two sections:
//    My household  join the roll call (or choose "Not now"), then your home,
//                  your buddy, and your privacy
//    I check on    be a volunteer buddy for neighbors
//

import SwiftUI

struct RollCallTabView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        if let me = auth.me, me.isResponder {
            ResponderHomeView()
        } else if let me = auth.me {
            MemberRollCallView(me: me)
        }
    }
}

private struct MemberRollCallView: View {
    let me: Me
    @Environment(AuthStore.self) private var auth
    @Environment(\.brand) private var brand
    @State private var section: Section = .household
    @State private var isJoining = false
    @State private var isWorking = false
    @State private var actionError: APIError?

    enum Section: Hashable { case household, buddy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Picker("Section", selection: $section) {
                        Text("My household").tag(Section.household)
                        Text("I check on").tag(Section.buddy)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("rollCallSection")

                    switch section {
                    case .household: householdSection
                    case .buddy: buddySection
                    }
                }
                .padding(Spacing.l)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Roll Call")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccountButton() }
                ToolbarItem(placement: .topBarTrailing) { AppearanceToolbarMenu() }
            }
            .refreshable { await auth.refresh() }
        }
        .fullScreenCover(isPresented: $isJoining) {
            ProfileWizardView(mode: .register, existing: nil, name: me.name) { _ in
                Task { await auth.refresh() }
            }
            .rollCallBrand()
        }
        .alert("Couldn't do that", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError?.message ?? "")
        }
    }

    // MARK: - My household

    @ViewBuilder
    private var householdSection: some View {
        if let householdID = me.householdId {
            ResidentHomeView(householdID: householdID)
                .id(householdID)
        } else if me.rollCallOptOut {
            optedOutCard
        } else {
            joinCard
        }
    }

    /// Asking, not assuming: join now, or "Not now".
    private var joinCard: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            BrandMark(size: 64)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.l)
            Text("Join the roll call?")
                .font(.title.weight(.bold)).fontDesign(.rounded)
            Text("When an emergency hits your area, RollCall asks if you're safe. If you don't answer, a neighbor checks on you, and responders know who still needs help.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                point("lock.fill", "Your details stay private until there's an emergency in your area.")
                point("hand.raised.fill", "It's your choice. You can leave anytime, and your data is deleted.")
                point("clock.fill", "Takes about 2 minutes.")
            }
            Button { isJoining = true } label: {
                Text("Join the roll call")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("joinRollCall")
            Button {
                Task { await setOptOut(true) }
            } label: {
                Text("Not now")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isWorking)
            .accessibilityIdentifier("notNow")
            Text("You can still use the Map and Incidents tabs without joining.")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .card()
    }

    private var optedOutCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label("You're not on the roll call", systemImage: "person.crop.circle.badge.xmark")
                .font(.headline)
                .accessibilityIdentifier("optedOut")
            Text("Responders won't know to check on you during an emergency. You can join anytime.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Join the roll call") { isJoining = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("joinRollCall")
        }
        .card()
    }

    private func point(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: symbol).foregroundStyle(brand)
        }
        .font(.subheadline)
    }

    // MARK: - I check on

    @ViewBuilder
    private var buddySection: some View {
        if me.isVolunteer {
            BuddyHomeView()
        } else {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.largeTitle)
                    .foregroundStyle(brand)
                Text("Be a volunteer buddy")
                    .font(.title2.weight(.bold)).fontDesign(.rounded)
                Text("Check on neighbors who might need help in an emergency, like seniors living alone. You only see someone's details after they accept you.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        isWorking = true
                        defer { isWorking = false }
                        do throws(APIError) { try await auth.setVolunteer(true, city: me.community?.city ?? "") } catch { actionError = error }
                    }
                } label: {
                    Text("Become a volunteer buddy")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking)
                .accessibilityIdentifier("becomeVolunteer")
            }
            .card()
        }
    }

    private func setOptOut(_ optOut: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do { try await auth.setRollCallOptOut(optOut) } catch { actionError = error }
    }
}
