//
//  LiveDataSheet.swift
//  RollCall
//
//  Where the live map data comes from, whether each source answered, a
//  switch to hide live data, and the demo Tornado Warning (for the demo video
//  and for judges on a day with no real severe weather).
//

import SwiftUI

struct LiveDataSheet: View {
    @Bindable var viewModel: MapViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show live data on the map", isOn: $viewModel.filters.showsLiveData)
                        .accessibilityIdentifier("liveDataToggle")
                } footer: {
                    Text("Live data is shown as diamonds. Community reports are circles.")
                }

                Section("Sources") {
                    if let feed = viewModel.hazardFeed {
                        ForEach(feed.sources, id: \.name) { source in
                            HStack {
                                Image(systemName: source.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(source.ok ? Color(.systemGreen) : Color(.systemOrange))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name).font(.app(.body))
                                    Text(source.ok ? "\(source.count) right now" : "Not answering. Showing its last update.")
                                        .font(.app(.callout)).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text("Updated \(feed.updatedAt.formatted(.relative(presentation: .named)))")
                            .font(.app(.callout)).foregroundStyle(.secondary)
                    } else if let error = viewModel.hazardError {
                        Text(error.message).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.setDemoWarning(on: !viewModel.isDemoWarningOn) }
                    } label: {
                        Label(viewModel.isDemoWarningOn ? "End the demo Tornado Warning" : "Start a demo Tornado Warning",
                              systemImage: "tornado")
                    }
                    .disabled(viewModel.isChangingDemo)
                    .accessibilityIdentifier("demoWarningButton")
                } header: {
                    Text("Demo")
                } footer: {
                    Text("Shows a realistic Tornado Warning near Greenville for 40 minutes, clearly labeled Demo. It's for practice and presentations. It isn't a real alert.")
                }

                if let note = viewModel.hazardFeed?.note {
                    Section { Text(note).font(.app(.callout)) }
                }
            }
            .navigationTitle("Live data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }.flat()
            }
        }
    }
}

/// The small "Live · 114" pill on the map that opens the sheet above.
struct LiveDataPill: View {
    let feed: HazardFeed?
    let hasError: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(hasError ? Color(.systemOrange) : Color(.systemGreen))
                    .frame(width: 8, height: 8)
                Text(feed.map { "Live · \($0.hazards.count)" } ?? "Live data")
                    .monospacedDigit()
            }
            .font(.app(.footnote).weight(.semibold))
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .floatingSurface(cornerRadius: 14)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(feed.map { "Live data, \($0.hazards.count) hazards" } ?? "Live data")
        .accessibilityHint("Shows where the data comes from, and the demo tornado warning")
        .accessibilityIdentifier("liveDataPill")
    }
}
