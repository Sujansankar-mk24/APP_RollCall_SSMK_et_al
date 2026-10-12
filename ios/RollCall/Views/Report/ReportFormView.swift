//
//  ReportFormView.swift
//  RollCall
//
//  The "Report incident" sheet:
//    911 banner
//    What's happening?  (type tiles)
//    Where?             (address search + map with a draggable pin)
//    Details            (short description)
//    Photo or video     (take one with the camera or pick one; checked by the AI)
//    [Send report]
//

import PhotosUI
import SwiftUI

struct ReportFormView: View {
    /// Called with the server's answer after a successful send.
    let onSubmitted: (ReportCreated) -> Void

    @State private var viewModel = ReportViewModel()
    @State private var pickedItem: PhotosPickerItem?
    @State private var confirmingDiscard = false
    @State private var addressSearch = AddressSearch()
    @State private var isShowingCamera = false
    @FocusState private var isEditingDescription: Bool
    @FocusState private var isSearchingAddress: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    EmergencyBanner()

                    formSection("What's happening?") {
                        TypePickerGrid(selection: $viewModel.selectedType)
                    }

                    formSection("Where?") { locationSection }

                    formSection("Details", note: "Optional") { descriptionField }

                    formSection("Photo or video", note: "Optional") { attachmentSection }

                    if let error = viewModel.submitError {
                        submitErrorCard(error)
                    }
                }
                .padding(Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Report incident")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if viewModel.hasChanges { confirmingDiscard = true } else { dismiss() }
                    }
                }
                // The "Done" button above the keyboard.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isEditingDescription = false
                        isSearchingAddress = false
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // While typing an address, the suggestions need the room.
                if !isSearchingAddress { sendBar }
            }
        }
        // Don't let a swipe throw away a half-written report by accident.
        .interactiveDismissDisabled(viewModel.hasChanges)
        .confirmationDialog("Discard this report?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard report", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .task { await viewModel.useCurrentLocation() }
        .onChange(of: pickedItem) { _, item in
            Task { await viewModel.loadAttachment(from: item) }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraCapture { capture in
                Task { await viewModel.useCapture(capture) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Sections

    private func formSection<Content: View>(_ title: String, note: String? = nil,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            addressField

            LocationPickerMap(coordinate: viewModel.coordinate, position: $viewModel.mapPosition) {
                viewModel.movePin(to: $0)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    Task { await viewModel.useCurrentLocation() }
                } label: {
                    Group {
                        if viewModel.isLocating {
                            ProgressView()
                        } else {
                            Image(systemName: "location.fill")
                        }
                    }
                    .frame(width: minimumTapSize, height: minimumTapSize)
                    .contentShape(Rectangle())
                }
                .foregroundStyle(Color.accentColor)
                .floatingSurface(cornerRadius: Radius.control)
                .padding(Spacing.s)
                .disabled(viewModel.isLocating)
                .accessibilityLabel("Use my current location")
            }

            Label {
                Text(viewModel.placeName ?? "Drag the pin or tap the map to mark the spot")
                    .foregroundStyle(viewModel.placeName == nil ? .secondary : .primary)
                    .accessibilityIdentifier("pinPlaceName")
            } icon: {
                Image(systemName: "mappin")
                    .foregroundStyle(Color(.systemRed))
            }
            .font(.subheadline)

            if let note = viewModel.locationNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Color(.systemOrange))
            }
        }
    }

    /// Type an address or place; pick a suggestion to move the pin there.
    private var addressField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search an address or place", text: $addressSearch.query)
                    .focused($isSearchingAddress)
                    .accessibilityIdentifier("addressSearchField")
                    .textContentType(.fullStreetAddress)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if addressSearch.isLookingUp {
                    ProgressView()
                } else if !addressSearch.query.isEmpty {
                    Button {
                        addressSearch.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .frame(width: minimumTapSize, height: minimumTapSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.leading, Spacing.m)
            .frame(minHeight: minimumTapSize)

            if isSearchingAddress && !addressSearch.suggestions.isEmpty {
                Divider()
                ForEach(addressSearch.suggestions) { suggestion in
                    Button {
                        Task {
                            if let place = await addressSearch.place(for: suggestion) {
                                viewModel.usePlace(place)
                                addressSearch.clear()
                                isSearchingAddress = false
                            } else {
                                viewModel.reportLocationLookupFailed()
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: minimumTapSize, alignment: .leading)
                        .padding(.horizontal, Spacing.m)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if suggestion.id != addressSearch.suggestions.last?.id {
                        Divider().padding(.leading, Spacing.m)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private var descriptionField: some View {
        VStack(alignment: .trailing, spacing: Spacing.xs) {
            TextField("What do you see? Landmarks help, like \"by the water tower on FM 1570\".",
                      text: $viewModel.description, axis: .vertical)
                .lineLimit(3...6)
                .focused($isEditingDescription)
                .padding(Spacing.m)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityLabel("Description")
            Text("\(viewModel.description.count) / \(ReportViewModel.maxDescriptionLength)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var attachmentSection: some View {
        if viewModel.isLoadingAttachment {
            HStack(spacing: Spacing.s) {
                ProgressView()
                Text("Loading…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        } else if let attachment = viewModel.attachment {
            attachmentPreview(attachment)
        } else {
            HStack(spacing: Spacing.s) {
                // The camera only exists on a real iPhone, not in the simulator.
                if CameraCapture.isAvailable {
                    Button {
                        isShowingCamera = true
                    } label: {
                        AttachmentChoiceLabel(systemImage: "camera.fill", title: "Take photo or video")
                    }
                    .buttonStyle(.plain)
                }
                PhotosPicker(selection: $pickedItem, matching: .any(of: [.images, .videos])) {
                    AttachmentChoiceLabel(systemImage: "photo.on.rectangle", title: "Choose from library")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Color.accentColor)

            Text(CameraCapture.isAvailable
                 ? "The AI checks it for fire, smoke and people."
                 : "The AI checks it for fire, smoke and people. (The simulator has no camera, so pick from the library.)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = viewModel.attachmentError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color(.systemRed))
            }
        }
    }

    private func attachmentPreview(_ attachment: Attachment) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Group {
                if let preview = attachment.preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.tertiarySystemFill)
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                if attachment.isVideo { PlayBadge() }
            }
            .accessibilityLabel(attachment.isVideo ? "Selected video" : "Selected photo")

            HStack {
                PhotosPicker(selection: $pickedItem, matching: .any(of: [.images, .videos])) {
                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                }
                Spacer()
                Button(role: .destructive) {
                    pickedItem = nil
                    viewModel.removeAttachment()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
            .font(.subheadline.weight(.medium))
            .frame(minHeight: minimumTapSize)
        }
    }

    private func submitErrorCard(_ error: APIError) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(.systemOrange))
            VStack(alignment: .leading, spacing: 2) {
                Text("Your report wasn't sent")
                    .font(.subheadline.weight(.semibold))
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Everything you entered is still here. Tap Send report to try again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemOrange).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Send button

    private var sendBar: some View {
        VStack(spacing: Spacing.xs) {
            Button {
                Task {
                    if let result = await viewModel.submit() {
                        onSubmitted(result)
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: Spacing.s) {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white)
                        Text("Sending…")
                    } else {
                        Image(systemName: "paperplane.fill")
                        Text("Send report")
                    }
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("sendReportButton")

            if viewModel.selectedType == nil {
                Text("Choose what's happening to send your report.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.s)
        .background(.bar)
    }
}

#Preview {
    ReportFormView { _ in }
}

/// One of the two dashed "add a photo or video" buttons.
private struct AttachmentChoiceLabel: View {
    let systemImage: String
    let title: String

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .contentShape(Rectangle())
    }
}
