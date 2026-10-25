//
//  BrandMark.swift
//  RollCall
//
//  The RollCall logo: neighbors joined in a circle around a shield with a
//  check mark (Assets > Logo, with its background removed so it sits on
//  light and dark pages alike). The app icon is in Assets > AppIcon, with
//  a light, a dark and a tinted version.
//
//  With `animatesCheck`, the shield starts empty and the check mark draws
//  itself in, like ticking a name on a roll call (used on the splash screen).
//

import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 88
    /// Not used anymore. Kept so older calls still work.
    var showsLines = true
    var animatesCheck = false

    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animatesCheck {
                Image("LogoNoCheck")
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        CheckMark()
                            .trim(from: 0, to: drawn)
                            .stroke(.white, style: StrokeStyle(lineWidth: size * 0.048, lineCap: .round, lineJoin: .round))
                    }
                    .onAppear {
                        if reduceMotion {
                            drawn = 1
                        } else {
                            withAnimation(.easeOut(duration: 0.55).delay(0.35)) { drawn = 1 }
                        }
                    }
            } else {
                Image("Logo").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// The logo's check mark, as a path: down to the bottom, then up to the
    /// right. The points match where it sits in the logo image.
    private struct CheckMark: Shape {
        nonisolated func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.width * 0.398, y: rect.height * 0.456))
            path.addLine(to: CGPoint(x: rect.width * 0.456, y: rect.height * 0.560))
            path.addLine(to: CGPoint(x: rect.width * 0.597, y: rect.height * 0.404))
            return path
        }
    }
}

#Preview {
    VStack {
        BrandMark(size: 200, animatesCheck: true)
        BrandMark(size: 80)
    }
    .padding(40)
    .sheetPage()
}
