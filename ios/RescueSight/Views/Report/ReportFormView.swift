//
//  ReportFormView.swift
//  RescueSight
//
//  The "Report incident" sheet:
//    911 banner
//    What's happening?  (type tiles)
//    Where?             (map with a draggable pin)
//    Details            (short description)
//    Photo or video     (optional, checked by the AI)
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
    @FocusState private var isEditingDescription: Bool
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
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") { isEditingDescription = false }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { sendBar }
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
            PhotosPicker(selection: $pickedItem, matching: .any(of: [.images, .videos])) {
                VStack(spacing: Spacing.s) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title)
                    Text("Add a photo or video")
                        .font(.subheadline.weight(.semibold))
                    Text("The AI checks it for fire, smoke and people.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

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
