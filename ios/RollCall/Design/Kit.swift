//
//  Kit.swift
//  RollCall
//
//  Small shared pieces of the Phantom/WHOOP-style look (see Sheet.swift):
//    CircleIconButton   a round button for close, back, help, edit
//    Avatar             a round profile picture, or initials when there's none
//    .successOverlay    a big ring with a check mark and "SAVED", for a moment
//

import SwiftUI
import UIKit

/// A round icon button on a card-colored circle (Phantom's back and close buttons).
struct CircleIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var size: CGFloat = minimumTapSize
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: size, height: size)
                .background(Color.paperRaised, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Someone's profile picture in a circle, or their initials on a soft
/// circle when they haven't added one.
struct Avatar: View {
    let url: URL?
    let name: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.1))
            Text(initials(name))
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.secondary)
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - "Saved" confirmation

extension View {
    /// Shows a big ring with a check mark and a word ("SAVED") over the
    /// screen for a moment, like WHOOP does, then hides it by itself.
    func successOverlay(isPresented: Binding<Bool>, text: LocalizedStringKey = "Saved") -> some View {
        overlay {
            if isPresented.wrappedValue {
                SuccessBadge(text: text)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(1.3))
                        withAnimation(.easeOut(duration: 0.25)) { isPresented.wrappedValue = false }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: isPresented.wrappedValue)
    }
}

private struct SuccessBadge: View {
    let text: LocalizedStringKey
    @State private var drawn = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            ZStack {
                Circle().stroke(Color(.systemGreen).opacity(0.25), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(Color(.systemGreen), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color(.systemGreen))
                    .scaleEffect(drawn ? 1 : 0.4)
                    .opacity(drawn ? 1 : 0)
            }
            .frame(width: 110, height: 110)
            Text(text)
                .font(.app(.headline))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(.white)
        }
        .padding(Spacing.xxl)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { drawn = true } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("successOverlay")
    }
}

// MARK: - Keyboard

extension View {
    /// For text boxes with more than one line: the Return key closes the
    /// keyboard (instead of starting a new line), so nobody gets stuck with
    /// the keyboard covering the screen.
    func returnClosesKeyboard(_ text: Binding<String>) -> some View {
        self
            .submitLabel(.done)
            .onChange(of: text.wrappedValue) { _, newValue in
                guard newValue.contains("\n") else { return }
                text.wrappedValue = newValue.replacingOccurrences(of: "\n", with: "")
                hideKeyboard()
            }
    }
}

/// Put the keyboard away, wherever it is.
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
