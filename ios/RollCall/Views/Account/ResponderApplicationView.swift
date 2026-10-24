//
//  ResponderApplicationView.swift
//  RollCall
//
//  "Apply as a first responder": firefighters, EMS, police and emergency
//  managers fill in their agency, role, badge number and the area they
//  serve, and add a photo of their ID. A person reviews it (there's no
//  government database to check against), and the ID photo is deleted
//  right after. Until then the account works like any other.
//

import SwiftUI

struct ResponderApplicationView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var application = APIClient.ResponderApplication()
    @State private var idPhoto: Data?
    @State private var isSending = false
    @State private var error: APIError?
    @State private var sent = false

    private var isComplete: Bool {
        application.agency.trimmed.count >= 2 && application.role.trimmed.count >= 2
            && application.badgeNumber.trimmed.count >= 2 && application.city.trimmed.count >= 2 && idPhoto != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    SheetTitle(title: "First responder", kicker: String(localized: "Apply"))
                    Text("Verified first responders can mark incidents responding or resolved. Residents can see who you are and report misuse, so every application is checked by a person.")
                        .font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LabeledField(label: "Agency", prompt: "e.g. Greenville Fire-Rescue", text: $application.agency,
                                 contentType: .organizationName, handwritten: false, identifier: "responderAgency")
                    LabeledField(label: "Your role", prompt: "e.g. Firefighter, Paramedic, Deputy", text: $application.role,
                                 contentType: .jobTitle, handwritten: false, identifier: "responderRole")
                    LabeledField(label: "Badge or employee number", prompt: "As printed on your ID", text: $application.badgeNumber,
                                 handwritten: false, identifier: "responderBadge")
                    LabeledField(label: "Town you serve", prompt: "Greenville", text: $application.city,
                                 contentType: .addressCity, handwritten: false, identifier: "responderCity")

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionLabel("Photo of your ID")
                        PhotoChooser(onPicked: { idPhoto = $0 }) {
                            Group {
                                if let idPhoto, let image = UIImage(data: idPhoto) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(height: 180).frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.paperCard, style: .continuous))
                                        .overlay(alignment: .bottomTrailing) {
                                            Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                                .font(.footnote.weight(.semibold))
                                                .padding(.horizontal, Spacing.m).padding(.vertical, 6)
                                                .background(.black.opacity(0.6), in: Capsule())
                                                .foregroundStyle(.white)
                                                .padding(Spacing.m)
                                        }
                                } else {
                                    VStack(spacing: Spacing.s) {
                                        Image(systemName: "person.text.rectangle").font(.system(size: 36))
                                        Text("Add a photo of your agency ID").font(.headline)
                                    }
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 150)
                                    .paperCard()
                                }
                            }
                        }
                        .accessibilityIdentifier("responderIDPhoto")
                        SheetNote(text: "Your ID photo is never shown to anyone in the app, and it's deleted as soon as it's reviewed.",
                                  systemImage: "lock.fill")
                    }

                    if let error {
                        Text(error.message).font(.callout).foregroundStyle(Color(.systemRed))
                    }
                    Button {
                        Task { await send() }
                    } label: {
                        HStack { if isSending { ProgressView().tint(Color.paper) }; Text("Send for review") }
                    }
                    .buttonStyle(InkButtonStyle())
                    .disabled(!isComplete || isSending)
                    .accessibilityIdentifier("sendResponderApplication")
                }
                .padding(Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .sheetPage()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }.flat()
            }
            .successOverlay(isPresented: $sent, text: "Sent for review")
            .onChange(of: sent) { if !sent { dismiss() } }
        }
        .onAppear {
            if application.city.isEmpty { application.city = auth.me?.community?.city ?? "" }
        }
    }

    private func send() async {
        guard let idPhoto else { return }
        isSending = true
        defer { isSending = false }
        do throws(APIError) {
            try await auth.applyAsResponder(application, idPhoto: idPhoto)
            sent = true
        } catch {
            self.error = error
        }
    }
}
