//
//  PersonProfileView.swift
//  RollCall
//
//  Someone else's profile, opened from your community, your buddy, or the
//  list of first responders: their picture, bio, badges ("Volunteer buddy",
//  "Looking for a buddy", "Away from home"), and what you're allowed to see.
//  The server decides that: the address only if you're in the same
//  community, the phone only if you're their buddy.
//
//  For someone in your community who joined the roll call, there's "Be their
//  buddy": an offer to check on them in an emergency, which they accept or
//  decline in Roll Call. Their buddy connections show as the same bubble web
//  the Community tab uses (tap a bubble to open that person).
//
//  For a first responder there's also "Report this responder", in case
//  someone is faking it, abusing the role or being reckless.
//

import SwiftUI

struct PersonProfileView: View {
    let personID: Int
    @State private var state: LoadState<Person> = .loading
    @State private var reports = false
    @State private var isOffering = false
    @State private var offerError: APIError?
    @State private var confirmsOffer = false
    @State private var openPerson: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                switch state {
                case .loading:
                    LoadingView()
                case .failed(let error):
                    SheetMessage(error: error, action: { Task { await load() } }).padding(Spacing.l)
                case .loaded(let person):
                    content(person).padding(Spacing.l)
                }
            }
            .sheetPage()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closePerson")
                }
                .flat()
            }
            .sheet(isPresented: $reports) {
                if let person = state.value { ReportResponderSheet(person: person) }
            }
            .sheet(item: $openPerson) { id in PersonProfileView(personID: id).sheetBrand() }
            .alert("Couldn't send the offer", isPresented: Binding(
                get: { offerError != nil }, set: { if !$0 { offerError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(offerError?.message ?? "")
            }
        }
        .task { await load() }
    }

    private func load() async {
        do { state = .loaded(try await APIClient.shared.fetchPerson(id: personID)) }
        catch { state = .failed(error) }
    }

    private func content(_ person: Person) -> some View {
        VStack(spacing: Spacing.l) {
            // The big picture and name, like the top of an Instagram profile.
            VStack(spacing: Spacing.m) {
                Avatar(url: person.photoURL, name: person.name, size: 112)
                Text(verbatim: person.name).font(.heading(30)).multilineTextAlignment(.center)
                if !person.bio.isEmpty {
                    Text(verbatim: person.bio)
                        .font(.app(.body))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PersonBadges(person: person)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("personHeader")

            if person.phone != nil || person.address != nil {
                contactCard(person)
            }

            if person.buddyOffer != .none {
                buddyOfferCard(person)
            }

            if person.connections.count > 1 {
                connectionsCard(person)
            }

            SheetCard {
                if let responder = person.responder {
                    infoRow("cross.case.fill", "First responder", "\(responder.role), \(responder.agency)")
                    infoRow("mappin.and.ellipse", "Serves", responder.city)
                }
                if let community = person.communityName {
                    infoRow("house.and.flag.fill", "Community",
                            person.isCommunityAdmin ? String(localized: "\(community) (admin)") : community)
                }
                infoRow("calendar", "On RollCall since", person.memberSince.formatted(.dateTime.month(.wide).year()))
            }

            if person.responder != nil {
                Button(role: .destructive) { reports = true } label: {
                    Label("Report this responder", systemImage: "flag.fill")
                }
                .buttonStyle(InkButtonStyle(prominent: false, destructive: true))
                .accessibilityIdentifier("reportResponder")
                SheetNote(text: "If someone is pretending to be a first responder, misusing the role, or closing incidents carelessly, tell us. Reports are private.",
                          systemImage: "lock.fill")
            }
        }
    }

    /// "Be their buddy", or where that offer stands.
    @ViewBuilder
    private func buddyOfferCard(_ person: Person) -> some View {
        switch person.buddyOffer {
        case .canOffer:
            VStack(alignment: .leading, spacing: Spacing.m) {
                Button { confirmsOffer = true } label: {
                    HStack {
                        if isOffering { ProgressView().tint(Color.paper) }
                        Label("Be \(person.firstName)'s buddy", systemImage: "hand.raised.fill")
                    }
                }
                .buttonStyle(InkButtonStyle())
                .disabled(isOffering)
                .accessibilityIdentifier("offerToBeBuddy")
                Text("You'd check on \(person.firstName) in an emergency. They get your offer in Roll Call and decide. You only see their household details if they accept.")
                    .font(.app(.callout)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .confirmationDialog("Offer to be \(person.firstName)'s buddy?", isPresented: $confirmsOffer,
                                titleVisibility: .visible) {
                Button("Send the offer") { Task { await offer(to: person) } }
                    .accessibilityIdentifier("confirmBuddyOffer")
            } message: {
                Text("If you aren't a volunteer buddy yet, this signs you up as one.")
            }
        case .asked:
            SheetNote(text: "You offered to be \(person.firstName)'s buddy. Waiting for them to accept.",
                      systemImage: "clock.fill")
                .accessibilityIdentifier("buddyOfferSent")
        case .checkingOn:
            SheetNote(text: "You check on \(person.firstName). They're in your list under I check on.",
                      systemImage: "person.2.fill")
        case .none:
            EmptyView()
        }
    }

    private func offer(to person: Person) async {
        isOffering = true
        defer { isOffering = false }
        do throws(APIError) {
            state = .loaded(try await APIClient.shared.offerToBeBuddy(personID: person.id))
        } catch {
            offerError = error
        }
    }

    /// Who they check on and who checks on them, as floating bubbles joined by
    /// lines (only matches inside your community, like the Community tab's web).
    private func connectionsCard(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel("Connections")
            ConnectionsWeb(members: person.connections, pairs: person.connectionPairs, bubbleSize: 64,
                           onOpenProfile: { id in if id != person.id { openPerson = id } })
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityIdentifier("personConnections")
            Text(connectionsSummary(person))
                .font(.app(.footnote)).foregroundStyle(.secondary)
                .padding(.leading, Spacing.xs)
        }
    }

    private func connectionsSummary(_ person: Person) -> String {
        let checksOn = person.connectionPairs.filter { $0.volunteerId == person.id }.count
        let checkedBy = person.connectionPairs.filter { $0.residentId == person.id }.count
        // Only the parts that apply, e.g. "Checked on by 1 neighbor".
        var parts: [String] = []
        // ^[...](inflect: true) makes it "1 neighbor" or "2 neighbors".
        if checksOn > 0 {
            parts.append(String(AttributedString(localized: "Checks on ^[\(checksOn) neighbor](inflect: true)").characters))
        }
        if checkedBy > 0 {
            parts.append(String(AttributedString(localized: "Checked on by ^[\(checkedBy) neighbor](inflect: true)").characters))
        }
        return parts.joined(separator: " · ")
    }

    /// Call, text and directions, only for what you're allowed to see.
    private func contactCard(_ person: Person) -> some View {
        VStack(spacing: Spacing.m) {
            if let phone = person.phone, let digits = Self.digits(phone) {
                HStack(spacing: Spacing.m) {
                    Button { open("tel:\(digits)") } label: { Label("Call", systemImage: "phone.fill") }
                        .buttonStyle(InkButtonStyle())
                        .accessibilityIdentifier("callPerson")
                    Button { open("sms:\(digits)") } label: { Label("Text", systemImage: "message.fill") }
                        .buttonStyle(InkButtonStyle(prominent: false))
                        .accessibilityIdentifier("textPerson")
                }
            }
            if let address = person.address {
                Button { open("maps://?daddr=\(address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") } label: {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "house.fill").foregroundStyle(.secondary)
                        Text(verbatim: address).font(.app(.body).weight(.medium)).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").foregroundStyle(.secondary)
                    }
                    .sheetBox(padding: Spacing.m)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Directions to \(address)")
            }
        }
    }

    private func infoRow(_ symbol: String, _ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24)
            Text(title).font(.app(.body))
            Spacer(minLength: Spacing.s)
            Text(verbatim: value).font(.app(.body)).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .sheetRow()
        .accessibilityElement(children: .combine)
    }

    private func open(_ link: String) {
        if let url = URL(string: link) { openURL(url) }
    }

    /// "(903) 555-0142" -> "9035550142", or nil if there are no digits.
    static func digits(_ phone: String) -> String? {
        let digits = phone.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }
}

/// The little badges under someone's name.
struct PersonBadges: View {
    let person: Person

    var body: some View {
        FlowLayout(spacing: 6) {
            if person.responder != nil {
                Stamp(text: String(localized: "Verified responder"), systemImage: "checkmark.seal.fill", color: Color(.systemBlue))
            }
            if person.isMyBuddy {
                Stamp(text: String(localized: "Your buddy"), systemImage: "person.2.fill", color: Color(.systemGreen))
            }
            if person.isVolunteer {
                Stamp(text: String(localized: "Volunteer buddy"), systemImage: "hand.raised.fill", color: Color(.systemTeal))
            }
            if person.wantsBuddy {
                Stamp(text: String(localized: "Looking for a buddy"), systemImage: "magnifyingglass", color: Color(.systemOrange))
            }
            if person.awayFromHome {
                Stamp(text: String(localized: "Away from home"), systemImage: "suitcase.fill", color: .secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Report a first responder: pick a reason, add details if you want.
private struct ReportResponderSheet: View {
    let person: Person
    @State private var reason: ResponderReportReason = .fake
    @State private var details = ""
    @State private var isSending = false
    @State private var sent = false
    @State private var error: APIError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    SheetTitle(verbatim: String(localized: "Report \(person.firstName)"), kicker: String(localized: "Private"))
                    SectionLabel("What's wrong?")
                    SheetCard {
                        ForEach(ResponderReportReason.allCases) { option in
                            Button { reason = option } label: {
                                HStack {
                                    Text(option.title).font(.app(.body))
                                    Spacer()
                                    Image(systemName: reason == option ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(reason == option ? Color.primary : Color.secondary)
                                }
                                .sheetRow()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(reason == option ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    LabeledField(label: "What happened? (optional)", prompt: "A few words help the review",
                                 text: $details, handwritten: false)
                    if let error {
                        Text(error.message).font(.app(.callout)).foregroundStyle(Color(.systemRed))
                    }
                    Button {
                        Task { await send() }
                    } label: {
                        HStack { if isSending { ProgressView().tint(Color.paper) }; Text("Send report") }
                    }
                    .buttonStyle(InkButtonStyle(destructive: true))
                    .disabled(isSending)
                    .accessibilityIdentifier("sendResponderReport")
                }
                .padding(Spacing.l)
            }
            .sheetPage()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }.flat()
            }
            .successOverlay(isPresented: $sent, text: "Report sent")
            .onChange(of: sent) { if !sent { dismiss() } }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do throws(APIError) {
            try await APIClient.shared.reportResponder(id: person.id, reason: reason, details: details.trimmed)
            sent = true
        } catch {
            self.error = error
        }
    }
}
