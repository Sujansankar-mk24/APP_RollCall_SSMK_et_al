//
//  ProfileWizardView.swift
//  RollCall
//
//  Setting up (or editing) a household, one calm step at a time:
//    1. Your home      name, phone, and your address (typed, then checked on a map)
//    2. Who lives here children, adults, 65+
//    3. What could make leaving hard   mobility, medical equipment, no car, animals
//    4. If something happens   language, emergency contact, a volunteer buddy
//    5. Review         check everything and agree to how it's shared
//
//  Short steps with big controls are easier for older residents than one
//  long form, and every step says why we ask.
//

import MapKit
import SwiftUI
import UIKit

struct ProfileWizardView: View {
    @State private var viewModel: ProfileWizardViewModel
    @Environment(\.brand) private var brand
    /// While typing, the Back/Next bar steps aside so it doesn't cover the form.
    @State private var isKeyboardUp = false
    @Environment(\.dismiss) private var dismiss
    let onSaved: (Household) -> Void

    init(mode: ProfileWizardViewModel.Mode, existing: Household?, name: String = "",
         onSaved: @escaping (Household) -> Void) {
        _viewModel = State(initialValue: ProfileWizardViewModel(mode: mode, existing: existing, name: name))
        self.onSaved = onSaved
    }

    private var isEditing: Bool { viewModel.mode != .register }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        StepProgress(current: viewModel.step.rawValue, total: ProfileWizardViewModel.Step.allCases.count)
                            .id("top")
                        stepContent
                            .id(viewModel.step)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .opacity))
                    }
                    .padding(Spacing.l)
                }
                // Every new step starts at its title, not wherever the last one was scrolled to.
                .onChange(of: viewModel.step) { scroller.scrollTo("top", anchor: .top) }
            }
            .scrollDismissesKeyboard(.interactively)
            .sheetPage()
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(isEditing ? "Edit household" : "Join the roll call")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                .flat()
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isKeyboardUp { bottomBar }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardUp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardUp = false
            }
            .animation(.snappy(duration: 0.3), value: viewModel.step)
            .alert("Couldn't save", isPresented: Binding(
                get: { viewModel.saveError != nil }, set: { if !$0 { viewModel.saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.saveError?.message ?? "")
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .home: homeStep
        case .people: peopleStep
        case .needs: needsStep
        case .contact: contactStep
        case .review: reviewStep
        }
    }

    private func stepHeader(_ title: LocalizedStringKey, _ why: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SheetTitle(title: title)
            Text(why)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // 1. Your home
    private var homeStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            stepHeader("Your home", "Responders use your address to reach you in an emergency.")
            LabeledField(label: "Your name", prompt: "First and last name", text: $viewModel.input.contactName,
                         contentType: .name, identifier: "nameField")
            LabeledField(label: "Phone (optional)", prompt: "So a buddy can call you", text: $viewModel.input.phone,
                         contentType: .telephoneNumber, keyboard: .phonePad, identifier: "phoneField")

            LabeledField(label: "Street address", prompt: "e.g. 1418 Pecan Hollow Dr", text: $viewModel.input.address,
                         contentType: .streetAddressLine1, identifier: "addressField")
            HStack(alignment: .top, spacing: Spacing.m) {
                LabeledField(label: "Town", prompt: "Greenville", text: $viewModel.input.city,
                             contentType: .addressCity, identifier: "cityField")
                LabeledField(label: "ZIP code", prompt: "75401", text: $viewModel.input.zipCode,
                             contentType: .postalCode, keyboard: .numberPad, identifier: "zipField")
                    .frame(maxWidth: 130)
            }
            .onChange(of: viewModel.addressText) { viewModel.addressChanged() }

            VStack(alignment: .leading, spacing: 6) {
                Text("Check the pin is on your home").sheetLabelStyle().foregroundStyle(.secondary)
                LocationPickerMap(coordinate: viewModel.coordinate, position: $viewModel.mapPosition) {
                    viewModel.movePin(to: $0)
                }
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        Task { await viewModel.useCurrentLocation() }
                    } label: {
                        Group {
                            if viewModel.isLocating { ProgressView() } else { Image(systemName: "location.fill") }
                        }
                        .frame(width: minimumTapSize, height: minimumTapSize)
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(Color.paper)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
                    .padding(Spacing.s)
                    .accessibilityLabel("Use my current location")
                }
                .overlay {
                    if !viewModel.hasPin {
                        Text(viewModel.isFindingAddress ? "Finding your address…" : "Type your address, or use your location")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
                            .background(Color.paper, in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous).strokeBorder(Color.ink.opacity(0.3), lineWidth: 1))
                            .allowsHitTesting(false)
                    }
                }
                if let note = viewModel.locationNote {
                    Label(note.text, systemImage: note.isGood ? "checkmark.circle.fill" : "info.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(note.isGood ? Color(.systemGreen) : Color(.systemOrange))
                        .accessibilityIdentifier("locationNote")
                } else {
                    Text("Drag the map or tap to move the pin if it's not exactly on your home.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    // 2. Who lives here
    private var peopleStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader("Who lives here?", "Responders plan for how many people to find, and who may need extra help.")
                .padding(.bottom, Spacing.l)
            SheetCard {
            CounterRow(title: "Children", subtitle: "Under 18", systemImage: "figure.child", value: $viewModel.input.children, identifier: "counter_children")
            CounterRow(title: "Adults", subtitle: "18 to 64", systemImage: "figure.stand", value: $viewModel.input.adults, identifier: "counter_adults")
            CounterRow(title: "65 and older", subtitle: "Seniors", systemImage: "figure.walk", value: $viewModel.input.seniors, identifier: "counter_seniors")
            }
            if viewModel.input.people == 1 {
                SheetNote(text: "You live alone. RollCall checks on people living alone sooner, because nobody else is there to help.",
                          systemImage: "person.fill")
                    .padding(.top, Spacing.l)
            }
        }
    }

    // 3. What could make leaving hard
    private var needsStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            stepHeader("What could make leaving hard?", "Tap anything that applies. This helps responders bring the right help first.")
            SheetCard {
                ToggleTile(title: "Mobility needs", subtitle: "Wheelchair, walker, or can't use stairs",
                           systemImage: "figure.roll", isOn: $viewModel.input.mobilityNeeds, identifier: "need_mobility")
                ToggleTile(title: "No vehicle", subtitle: "No way to drive out on your own",
                           systemImage: "car.side.fill", isOn: $viewModel.input.noVehicle, identifier: "need_vehicle")
                ToggleTile(title: "Pets", subtitle: "Dogs, cats, or other pets at home",
                           systemImage: "pawprint.fill", isOn: $viewModel.input.pets, identifier: "need_pets")
                ToggleTile(title: "Livestock", subtitle: "Horses, cattle, or other farm animals",
                           systemImage: "hare.fill", isOn: $viewModel.input.livestock, identifier: "need_livestock")
            }

            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionLabel("Powered medical equipment")
                Text("If the power goes out, people who rely on this are checked first.")
                    .font(.callout).foregroundStyle(.secondary)
                FlowLayout(spacing: Spacing.s) {
                    ForEach(MedicalEquipment.allCases) { item in
                        SelectChip(title: item.title, systemImage: item.symbol,
                                   isSelected: viewModel.input.medicalEquipment.contains(item)) {
                            viewModel.toggle(item)
                        }
                        .accessibilityIdentifier("equipment_\(item.rawValue)")
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Anything else responders should know? (optional)").sheetLabelStyle().foregroundStyle(.secondary)
                TextField(text: $viewModel.input.notes,
                          prompt: Text("For example: \"I'm deaf, please knock loudly\"").font(.body),
                          axis: .vertical) { Text("Anything else responders should know?") }
                    .sheetEntryStyle()
                    .lineLimit(2...5)
                    .padding(Spacing.m)
                    .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
            }
        }
    }

    // 4. If something happens
    private var contactStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            stepHeader("If something happens", "How we reach you, and who else should know.")

            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionLabel("Your language")
                HStack(spacing: Spacing.m) {
                    ForEach(HouseholdLanguage.allCases) { language in
                        let selected = viewModel.input.language == language
                        Button { viewModel.input.language = language } label: {
                            HStack(spacing: Spacing.s) {
                                Image(systemName: selected ? "checkmark" : "globe").font(.headline)
                                Text(language.nativeName).font(.sheetHeading)
                            }
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .foregroundStyle(selected ? Color.paper : Color.primary)
                            .background(selected ? brand : Color.paperRaised, in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous).strokeBorder(selected ? brand : Color.primary.opacity(0.25), lineWidth: 1.5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier("language_\(language.rawValue)")
                    }
                }
            }

            LabeledField(label: "Emergency contact (optional)", prompt: "Name of a relative or friend",
                         text: $viewModel.input.emergencyContactName, contentType: .name)
            LabeledField(label: "Their phone (optional)", prompt: "(903) 555-0100",
                         text: $viewModel.input.emergencyContactPhone, contentType: .telephoneNumber, keyboard: .phonePad)

            Toggle(isOn: $viewModel.input.wantsBuddy) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Ask a neighbor to check on me", systemImage: "person.2.wave.2.fill")
                        .font(.sheetHeading)
                    Text("A volunteer buddy will come by if you don't answer during an emergency. You choose who.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(brand)
            .sheetBox(padding: Spacing.m)
            .accessibilityIdentifier("wantsBuddyToggle")
        }
    }

    // 5. Review
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            stepHeader("Check and finish", "Make sure this is right. You can change it anytime.")

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Name").sheetLabelStyle().foregroundStyle(.secondary)
                Text(verbatim: viewModel.input.contactName.isEmpty ? String(localized: "Not added") : viewModel.input.contactName)
                    .sheetEntryStyle(large: true)
                Text("Address").sheetLabelStyle().foregroundStyle(.secondary)
                    .padding(.top, Spacing.xs)
                Text(verbatim: "\(viewModel.input.address), \(viewModel.input.city) \(viewModel.input.zipCode)")
                    .sheetEntryStyle()
                TagChips(tags: previewTags)
                    .padding(.top, Spacing.xs)
            }
            .sheetBox()

            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionLabel("Who can see this")
                SheetCard {
                sharingRow("person.fill", "You", "Always. You can edit or delete it anytime.")
                if viewModel.input.wantsBuddy {
                    sharingRow("person.2.wave.2.fill", "Your volunteer buddy", "Your name, address, phone and needs, so they can check on you.")
                }
                sharingRow("cross.case.fill", "Responders", "Only during an emergency in your area.")
                sharingRow("eye.slash.fill", "Anyone else", "Never. Your information is never sold.")
                }
            }
            // The "I agree" switch sits in the bottom bar, right above Join,
            // so it's always on screen next to the button it unlocks.
        }
    }

    private var previewTags: [NeedTag] {
        let i = viewModel.input
        var tags = [NeedTag(i.people == 1 ? "1 person" : "\(i.people) people", symbol: "person.2.fill", tint: .secondary)]
        if i.seniors > 0 { tags.append(NeedTag("65+", symbol: "figure.walk", tint: .orange)) }
        if i.children > 0 { tags.append(NeedTag(i.children == 1 ? "1 child" : "\(i.children) children", symbol: "figure.child", tint: .orange)) }
        for item in i.medicalEquipment { tags.append(NeedTag(item.title, symbol: item.symbol, tint: .red)) }
        if i.mobilityNeeds { tags.append(NeedTag("Mobility needs", symbol: "figure.roll", tint: .red)) }
        if i.noVehicle { tags.append(NeedTag("No vehicle", symbol: "car.side.fill", tint: .orange)) }
        if i.pets { tags.append(NeedTag("Pets", symbol: "pawprint.fill", tint: .secondary)) }
        if i.livestock { tags.append(NeedTag("Livestock", symbol: "hare.fill", tint: .secondary)) }
        tags.append(NeedTag(verbatim: i.language.nativeName, symbol: "globe", tint: brand))
        return tags
    }

    private func sharingRow(_ symbol: String, _ who: LocalizedStringKey, _ what: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(who).font(.headline)
                Text(what).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheetRow()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Back / Next

    /// Joining needs a clear "yes" to the sharing rules shown above it.
    private var consentToggle: some View {
        Toggle(isOn: $viewModel.consent) {
            Text("I agree to share this information as described above.")
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(brand)
        .accessibilityIdentifier("consentToggle")
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.s) {
            if viewModel.isLastStep && !isEditing {
                consentToggle
            } else if let missing = viewModel.whatsMissing {
                Text(missing).font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.m) {
                if viewModel.step != .home {
                    Button("Back") { hideKeyboard(); viewModel.goBack() }
                        .buttonStyle(InkButtonStyle(prominent: false))
                        .frame(width: 110)
                    .accessibilityIdentifier("wizardBack")
                }
                Button {
                    hideKeyboard()
                    if viewModel.isLastStep {
                        Task {
                            if let saved = await viewModel.save() {
                                onSaved(saved)
                                dismiss()
                            }
                        }
                    } else {
                        viewModel.goNext()
                    }
                } label: {
                    HStack(spacing: Spacing.s) {
                        if viewModel.isSaving { ProgressView().tint(Color.paper) }
                        Text(viewModel.isLastStep ? (isEditing ? "Save changes" : "Join RollCall") : "Next")
                    }
                }
                .buttonStyle(InkButtonStyle())
                .disabled(!viewModel.canContinue)
                .accessibilityIdentifier("wizardNext")
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.s)
        .background(Color.paper)
        .shadow(color: .black.opacity(0.06), radius: 8, y: -2)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    ProfileWizardView(mode: .register, existing: nil) { _ in }
}
