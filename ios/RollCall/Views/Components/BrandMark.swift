//
//  BrandMark.swift
//  RollCall
//
//  The RollCall logo: neighbors joined in a circle around the name.
//  (Assets > Logo, with its background removed. In dark mode the middle
//  turns white with black letters, so it doesn't sink into the dark page.)
//  The app icon is in Assets > AppIcon, with light, dark and tinted versions.
//
//  LoadingLogo is the same logo as a loading animation: the ring of people
//  spins once around the middle, rests for a moment, and goes again.
//

import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 88
    /// Not used anymore. Kept so older calls still work.
    var showsLines = true
    /// Spin the ring of people, like a loading animation.
    var animatesCheck = false

    var body: some View {
        Group {
            if animatesCheck {
                LoadingLogo(size: size)
            } else {
                Image("Logo").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The logo with its ring of people spinning around the middle, then
/// resting, over and over. Used on the splash screen and while things load.
struct LoadingLogo: View {
    var size: CGFloat = 64
    @State private var turns: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The middle of the circle in the image (it's a little off the image's center).
    private static let pivot = UnitPoint(x: 0.507, y: 0.498)

    var body: some View {
        ZStack {
            Image("LogoRing").resizable().scaledToFit()
                .rotationEffect(.degrees(turns * 360), anchor: Self.pivot)
            Image("LogoCenter").resizable().scaledToFit()
        }
        .frame(width: size, height: size)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 1.1)) { turns += 1 }   // spin once...
                try? await Task.sleep(for: .seconds(2.1))                 // ...then rest a second
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A screen-sized "loading" state: the spinning logo, and an optional line.
struct LoadingView: View {
    var text: LocalizedStringKey? = nil

    var body: some View {
        VStack(spacing: Spacing.m) {
            LoadingLogo(size: 64)
            if let text {
                Text(text).font(.app(.callout)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

#Preview {
    VStack(spacing: 40) {
        LoadingLogo(size: 200)
        BrandMark(size: 80)
    }
    .padding(40)
    .sheetPage()
}
