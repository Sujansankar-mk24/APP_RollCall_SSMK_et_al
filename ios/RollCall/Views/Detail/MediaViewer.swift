//
//  MediaViewer.swift
//  RollCall
//
//  Full-screen view of one photo or video. A switch at the top flips
//  between the original and the "AI view" with detection boxes, so you can
//  see exactly what the AI saw.
//

import AVKit
import SwiftUI

struct MediaViewer: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case original, ai
        var id: Self { self }
    }

    @State private var mode: Mode
    @State private var player: AVPlayer?

    init(item: MediaItem) {
        self.item = item
        // Open on the AI view if the AI found something; it's the most useful picture.
        _mode = State(initialValue: item.analysis.foundSomething ? .ai : .original)
    }

    private var hasAIView: Bool { item.annotatedURL != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .safeAreaInset(edge: .bottom) { caption }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
                if hasAIView {
                    ToolbarItem(placement: .principal) {
                        Picker("View", selection: $mode) {
                            Text(item.kind == .video ? "Video" : "Original").tag(Mode.original)
                            Text(item.kind == .video ? "AI best frame" : "AI view").tag(Mode.ai)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 230)
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var content: some View {
        if mode == .ai, let annotated = item.annotatedURL {
            RemoteImage(url: annotated, contentMode: .fit)
                .accessibilityLabel("AI view: \(item.analysis.shortSummary)")
        } else if item.kind == .video {
            VideoPlayer(player: player)
                .onAppear {
                    if player == nil, let url = item.fileURL {
                        player = AVPlayer(url: url)
                    }
                    player?.play()
                }
                .onDisappear { player?.pause() }
        } else {
            RemoteImage(url: item.fileURL, contentMode: .fit)
                .accessibilityLabel("Photo")
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.analysis.shortSummary)
                .font(.headline)
            Group {
                if item.analysis.lowLightUsed {
                    Text("This picture was dark, so it was brightened before the AI looked for people.")
                }
                if item.kind == .video, item.analysis.framesAnalyzed > 0 {
                    Text("The AI checked \(item.analysis.framesAnalyzed) frames (about one per second) and shows the most informative one.")
                }
                Text("Added \(item.createdAt.formatted(.relative(presentation: .named)))")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }
}
