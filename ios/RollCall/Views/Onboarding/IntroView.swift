//
//  IntroView.swift
//  RollCall
//
//  The splash screen (the logo on black while the app checks who's signed
//  in), and three short intro pages shown the first time someone opens the
//  app, before they make an account:
//    1. Know who's safe          the roll call
//    2. See danger near you      live data and warnings on the map
//    3. Neighbors check on neighbors   buddies and communities
//

import SwiftUI

/// The logo on black, like the first screen of WHOOP or Phantom.
struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            BrandMark(size: 96)
                .environment(\.brand, .white)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(duration: 0.6)) { appeared = true } }
        .accessibilityLabel("RollCall")
        .accessibilityIdentifier("splash")
    }
}

struct IntroView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let color: Color
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    private let pages = [
        Page(id: 0, symbol: "person.crop.circle.badge.checkmark", color: Color(.systemGreen),
             title: "Know who's safe",
             text: "When a tornado, fire or flood hits your area, RollCall asks everyone who joined if they're safe. One tap answers."),
        Page(id: 1, symbol: "location.viewfinder", color: Color(.systemOrange),
             title: "See danger near you",
             text: "Live fires, storm warnings and floods from NASA and the National Weather Service, with a warning when you're close to one."),
        Page(id: 2, symbol: "person.2.wave.2.fill", color: Color(.systemBlue),
             title: "Neighbors check on neighbors",
             text: "A volunteer buddy from your community checks on you if you don't answer. Nobody gets left behind."),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    pageDots
                    Spacer()
                    Button("Skip", action: onFinish)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(minWidth: minimumTapSize, minHeight: minimumTapSize)
                        .opacity(page < pages.count - 1 ? 1 : 0)
                        .accessibilityIdentifier("skipIntro")
                }
                .padding(.horizontal, Spacing.l)

                TabView(selection: $page) {
                    ForEach(pages) { item in
                        VStack(spacing: Spacing.xl) {
                            Spacer()
                            Image(systemName: item.symbol)
                                .font(.system(size: 110, weight: .semibold))
                                .foregroundStyle(item.color)
                                .symbolRenderingMode(.hierarchical)
                                .frame(height: 200)
                            VStack(spacing: Spacing.m) {
                                Text(item.title)
                                    .font(.system(.largeTitle, weight: .bold))
                                    .multilineTextAlignment(.center)
                                Text(item.text)
                                    .font(.title3)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, Spacing.xl)
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                Button {
                    if page < pages.count - 1 {
                        withAnimation(.snappy) { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < pages.count - 1 ? "Next" : "Get started")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.l)
                .accessibilityIdentifier("introNext")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(pages) { item in
                Capsule()
                    .fill(item.id == page ? Color.white : Color.white.opacity(0.3))
                    .frame(width: item.id == page ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: page)
        .accessibilityElement()
        .accessibilityLabel("Page \(page + 1) of \(pages.count)")
    }
}
