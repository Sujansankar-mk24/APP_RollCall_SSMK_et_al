//
//  ProfileView.swift
//  RollCall
//
//  Your profile (from the gear): your picture (camera or library), name,
//  bio and phone, the badges other people see, your roll call, buddy and
//  community, the first responder application, and Sign out.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var editing: EditField?
    @State private var showsApplication = false
    @State private var showsPreview = false
    @State private var saved = false
    @State private var error: APIError?
    @State private var isUploading = false

    enum EditField: String, Identifiable {
        case name, bio, phone
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let me = auth.me {
                    VStack(spacing: Spacing.l) {
                        header(me)
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SectionLabel("Profile")
                            SheetCard {
                                editRow("Name", me.name, field: .name)
                                editRow("Bio", me.bio.isEmpty ? String(localized: "Add a few words about you") : me.bio, field: .bio)
                                editRow("Phone", me.phone.isEmpty ? String(localized: "Only your buddy sees it") : me.phone, field: .phone)
                            }
                            Button { showsPreview = true } label: {
                                Label("See what neighbors see", systemImage: "eye")
                                    .font(.callout.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: minimumTapSize)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("previewProfile")
                        }
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SectionLabel("Your RollCall")
                            SheetCard {
                                row("house.fill", "Roll call", rollCallStatus(me))
                                if !me.isResponder {
                                    row("person.2.wave.2.fill", "Volunteer buddy",
                                        me.isVolunteer ? String(localized: "Yes, you check on neighbors") : String(localized: "Not yet"))
                                    row("house.and.flag.fill", "Community", communityStatus(me))
                                }
                                row(auth.serverURL == ServerSettings.thisMac ? "desktopcomputer" : "network",
                                    "Server", ServerSettings.displayName(for: auth.serverURL))
                            }
                        }
                        responderSection(me)
                        VStack(spacing: Spacing.m) {
                            Button(role: .destructive) {
                                dismiss()
                                Task { await auth.signOut() }
                            } label: {
                                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                            .buttonStyle(InkButtonStyle(prominent: false, destructive: true))
                            .accessibilityIdentifier("signOut")
                            SheetNote(text: "You stay signed in on this phone until you sign out.")
                        }
                    }
                    .padding(Spacing.l)
                }
            }
            .sheetPage()
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("closeProfile")
                }
                .flat()
            }
            .sheet(item: $editing) { field in
                EditProfileFieldSheet(field: field) { saved = true }.sheetBrand()
            }
            .sheet(isPresented: $showsApplication) {
                ResponderApplicationView().sheetBrand()
            }
            .sheet(isPresented: $showsPreview) {
                if let me = auth.me { PersonProfileView(personID: me.id).sheetBrand() }
            }
            .successOverlay(isPresented: $saved)
            .alert("Couldn't save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error?.message ?? "")
            }
        }
        .presentationBackground(Color.paper)
    }

    /// The big round picture with a pencil, then the name and badges.
    private func header(_ me: Me) -> some View {
        VStack(spacing: Spacing.m) {
            PhotoChooser(onPicked: { jpeg in Task { await setPhoto(jpeg) } }) {
                Avatar(url: me.photoURL, name: me.name, size: 120)
                    .overlay {
                        if isUploading { ProgressView().controlSize(.large) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 40, height: 40)
                            .background(Color.paperRaised, in: Circle())
                            .overlay(Circle().strokeBorder(Color.paper, lineWidth: 3))
                    }
            }
            .accessibilityLabel(me.photoUrl == nil ? "Add a profile picture" : "Change your profile picture")
            .accessibilityIdentifier("profilePhoto")
            if me.photoUrl != nil {
                Button("Remove picture", role: .destructive) { Task { await setPhoto(nil) } }
                    .font(.footnote.weight(.semibold))
            }
            VStack(spacing: 4) {
                Text(verbatim: me.name).font(.title.weight(.bold))
                Text(verbatim: me.email).font(.subheadline).foregroundStyle(.secondary)
            }
            badges(me)
        }
        .frame(maxWidth: .infinity)
    }

    private func badges(_ me: Me) -> some View {
        FlowLayout(spacing: 6) {
            if me.isResponder {
                Stamp(text: String(localized: "Verified responder"), systemImage: "checkmark.seal.fill", color: Color(.systemBlue))
            }
            if me.isVolunteer {
                Stamp(text: String(localized: "Volunteer buddy"), systemImage: "hand.raised.fill", color: Color(.systemTeal))
            }
            if let community = me.community, community.status == .member {
                Stamp(text: community.name, systemImage: "house.and.flag.fill", color: .secondary)
            }
            if me.awayFromHome {
                Stamp(text: String(localized: "Away from home"), systemImage: "suitcase.fill", color: Color(.systemOrange))
            }
        }
    }

    @ViewBuilder
    private func responderSection(_ me: Me) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel("First responder")
            switch me.responderStatus {
            case .approved:
                SheetCard {
                    row("checkmark.seal.fill", "Verified", "\(me.responderRole), \(me.responderAgency)")
                    row("mappin.and.ellipse", "Serves", me.responderCity)
                }
                SheetNote(text: "You can mark incidents responding or resolved. Residents can see your profile and report misuse.",
                          systemImage: "cross.case")
            case .pending:
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Stamp(text: String(localized: "Waiting for review"), systemImage: "hourglass", color: Color(.systemOrange))
                    Text("\(me.responderRole), \(me.responderAgency)").font(.headline)
                    Text("A person checks your ID and badge number. Your ID photo is deleted right after.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .sheetBox()
                .accessibilityIdentifier("responderPending")
            case .none, .rejected:
                Button { showsApplication = true } label: {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "cross.case.fill").font(.title3).frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(me.responderStatus == .rejected ? "Apply again as a first responder" : "Are you a first responder?")
                                .font(.headline)
                            Text("Firefighters, EMS, police and emergency managers can apply to update incidents.")
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .sheetBox(padding: Spacing.l)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("applyAsResponder")
            }
        }
    }

    private func editRow(_ title: LocalizedStringKey, _ value: String, field: EditField) -> some View {
        Button { editing = field } label: {
            HStack(spacing: Spacing.m) {
                Text(title).font(.body)
                Spacer(minLength: Spacing.m)
                Text(verbatim: value).font(.body).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .sheetRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("edit_\(field.rawValue)")
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24)
            Text(title).font(.body)
            Spacer()
            Text(verbatim: value).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .sheetRow()
        .accessibilityElement(children: .combine)
    }

    private func setPhoto(_ jpeg: Data?) async {
        isUploading = true
        defer { isUploading = false }
        do throws(APIError) {
            try await auth.setProfilePhoto(jpeg)
            saved = true
        } catch {
            self.error = error
        }
    }

    private func rollCallStatus(_ me: Me) -> String {
        if me.isResponder { return String(localized: "Responder account") }
        if me.householdId != nil { return String(localized: "You're on it") }
        return me.rollCallOptOut ? String(localized: "You chose not now") : String(localized: "Not joined yet")
    }

    private func communityStatus(_ me: Me) -> String {
        guard let community = me.community else { return String(localized: "None yet") }
        switch community.status {
        case .pending: return String(localized: "Waiting to join \(community.name)")
        case .member: return community.isAdmin ? String(localized: "\(community.name) (admin)") : community.name
        }
    }
}

/// Change your name, bio or phone.
private struct EditProfileFieldSheet: View {
    let field: ProfileView.EditField
    let onSaved: () -> Void
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSaving = false
    @State private var error: APIError?

    private var title: LocalizedStringKey {
        switch field {
        case .name: "Name"
        case .bio: "Bio"
        case .phone: "Phone"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.l) {
                switch field {
                case .name:
                    LabeledField(label: "Your name", prompt: "First and last name", text: $text,
                                 contentType: .name, handwritten: false, identifier: "editField")
                case .bio:
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Bio").sheetLabelStyle().foregroundStyle(.secondary)
                        TextField("Nurse at Hunt Regional. Two dogs. Happy to help neighbors.", text: $text, axis: .vertical)
                            .lineLimit(3...5)
                            .padding(Spacing.m)
                            .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
                            .accessibilityIdentifier("editField")
                        Text("\(text.count) / 160").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                case .phone:
                    LabeledField(label: "Phone", prompt: "(903) 555-0100", text: $text,
                                 contentType: .telephoneNumber, keyboard: .phonePad, handwritten: false, identifier: "editField")
                    SheetNote(text: "Only your volunteer buddy sees it, so they can call or text you in an emergency.",
                              systemImage: "lock.fill")
                }
                if let error {
                    Text(error.message).font(.callout).foregroundStyle(Color(.systemRed))
                }
                Button {
                    Task { await save() }
                } label: {
                    HStack { if isSaving { ProgressView().tint(Color.paper) }; Text("Save") }
                }
                .buttonStyle(InkButtonStyle())
                .disabled(isSaving || (field == .name && text.trimmed.isEmpty) || text.count > 160)
                .accessibilityIdentifier("saveField")
                Spacer()
            }
            .padding(Spacing.l)
            .sheetPage()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }.flat()
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            switch field {
            case .name: text = auth.me?.name ?? ""
            case .bio: text = auth.me?.bio ?? ""
            case .phone: text = auth.me?.phone ?? ""
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var change = APIClient.ProfileChange()
        switch field {
        case .name: change.name = text.trimmed
        case .bio: change.bio = text.trimmed
        case .phone: change.phone = text.trimmed
        }
        do throws(APIError) {
            try await auth.updateProfile(change)
            onSaved()
            dismiss()
        } catch {
            self.error = error
        }
    }
}
