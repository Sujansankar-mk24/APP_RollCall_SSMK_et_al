//
//  WelcomeView.swift
//  RollCall
//
//  "Welcome to RollCall": the very first screen, shown only once. A real
//  photo of a rescue during Hurricane Harvey (Port Arthur, Texas, 2017, by
//  the South Carolina National Guard, public domain, from Wikimedia
//  Commons), what RollCall does, and two ways in: make an account, or sign
//  in to one you already have. About RollCall can replay it (isReplay), and
//  then the buttons are "See how it works" and "Close".
//

import SwiftUI

struct WelcomeView: View {
    let onGetStarted: () -> Void
    let onSignIn: () -> Void
    /// Opened again from About RollCall, by someone already signed in.
    var isReplay = false
    @State private var appeared = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // The photo across the top, fading into the page.
                Image("WelcomePhoto")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height * 0.46 + geometry.safeAreaInsets.top)
                    .clipped()
                    .overlay {
                        LinearGradient(stops: [.init(color: .black.opacity(0.3), location: 0),
                                               .init(color: .clear, location: 0.2),
                                               .init(color: .clear, location: 0.6),
                                               .init(color: Color.paper, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .accessibilityLabel("A rescuer is lowered from a helicopter over a flooded neighborhood in Port Arthur, Texas, after Hurricane Harvey")

                VStack(alignment: .leading, spacing: Spacing.l) {
                    HStack(spacing: Spacing.m) {
                        BrandMark(size: 58)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Welcome to").font(.title3.weight(.medium)).foregroundStyle(.secondary)
                            Text("RollCall").font(.system(size: 38, weight: .bold))
                        }
                    }
                    Text("When disaster hits North Texas, the people who can't get out alone are the easiest to miss. RollCall makes sure someone checks on every one of them.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        feature("person.crop.circle.badge.checkmark", "Let everyone know you're safe, or that you need help")
                        feature("person.2.wave.2.fill", "A neighbor checks on you if you don't answer")
                        feature("location.viewfinder", "Live fire and storm warnings where you are")
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: Spacing.m) {
                        Button(action: onGetStarted) { Text(isReplay ? "See how it works" : "Get started") }
                            .buttonStyle(InkButtonStyle())
                            .accessibilityIdentifier("welcomeGetStarted")
                        Button(action: onSignIn) { Text(isReplay ? "Close" : "I already have an account") }
                            .buttonStyle(OutlinePillStyle())
                            .accessibilityIdentifier("welcomeSignIn")
                    }
                    Text("Photo: a rescue in Port Arthur, Texas, after Hurricane Harvey. South Carolina National Guard, public domain.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, -Spacing.xl)   // tuck the title into the photo's fade
                .padding(.bottom, Spacing.s)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(Color.paper.ignoresSafeArea())
        .sheetBrand()
        .onAppear { withAnimation(.easeOut(duration: 0.6).delay(0.15)) { appeared = true } }
    }

    private func feature(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.ink).frame(width: 26)
        }
    }
}

/// A pill with just an outline, like WHOOP's "I do not have a device" button.
struct OutlinePillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Color.primary)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
