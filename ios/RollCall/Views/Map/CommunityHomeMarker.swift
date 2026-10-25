//
//  CommunityHomeMarker.swift
//  RollCall
//
//  A neighbor's home in the map's "My community" view: a small house dot,
//  and when you're zoomed in close (about a quarter mile or less), a bubble
//  above it with their picture. Tap the bubble to pop it (it floats back
//  after 5 seconds); tap the house to open their profile.
//

import SwiftUI

struct CommunityHomeMarker: View {
    let home: CommunityHome
    /// Bubbles only show when the map is zoomed in close.
    let showsBubble: Bool
    let onOpen: () -> Void

    @State private var popped = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if showsBubble && !popped {
                    Avatar(url: home.photoURL, name: home.name, size: 34)
                        .frame(width: 42, height: 42)
                        .glassBubble()
                        .overlay {
                            if !home.hasBuddy {
                                Circle().strokeBorder(Color(.systemOrange), lineWidth: 2)
                            }
                        }
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                        .onTapGesture { pop() }
                        .accessibilityLabel("\(home.name)'s bubble")
                        .accessibilityHint("Pops the bubble")
                }
                if popped && showsBubble { PopBurst(size: 42) }
            }
            .frame(height: showsBubble ? 44 : 0)

            Button(action: onOpen) {
                Image(systemName: home.awayFromHome ? "suitcase.fill" : "house.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.themeAccent, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .frame(width: minimumTapSize, height: minimumTapSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(home.name)'s home")
            .accessibilityHint("Opens their profile")
            .accessibilityIdentifier("home_\(home.userId)")
        }
        .animation(.spring(duration: 0.35, bounce: 0.35), value: showsBubble)
        .animation(.spring(duration: 0.35, bounce: 0.35), value: popped)
    }

    private func pop() {
        popped = true
        Task {
            try? await Task.sleep(for: .seconds(5))
            popped = false
        }
    }
}
