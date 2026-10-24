//
//  UserLocationDot.swift
//  RollCall
//
//  "You are here", drawn like Google Maps: a blue dot with a white ring, a
//  soft halo, and a light-blue cone pointing the way the phone faces.
//

import SwiftUI

struct UserLocationDot: View {
    /// Which way the cone points on screen, in degrees (0 = up). nil hides it.
    let coneAngle: Double?

    private let blue = Color(red: 0.10, green: 0.45, blue: 0.95)

    var body: some View {
        ZStack {
            if let coneAngle {
                Cone()
                    .fill(RadialGradient(colors: [blue.opacity(0.45), blue.opacity(0)],
                                         center: .bottom, startRadius: 0, endRadius: 46))
                    .frame(width: 70, height: 46)
                    .offset(y: -23)                       // the cone's tip sits on the dot
                    .rotationEffect(.degrees(coneAngle))
                    .animation(.easeOut(duration: 0.25), value: coneAngle)
            }
            Circle().fill(blue.opacity(0.18)).frame(width: 44, height: 44)
            Circle().fill(.white).frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            Circle().fill(blue).frame(width: 16, height: 16)
        }
        .frame(width: 92, height: 92)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Your location")
        .accessibilityIdentifier("userLocationDot")
    }

    /// A wedge that opens upward from a point at the bottom middle.
    private nonisolated struct Cone: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.15))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.15),
                              control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.15))
            path.closeSubpath()
            return path
        }
    }
}

#Preview {
    UserLocationDot(coneAngle: 30).padding().background(Color.gray.opacity(0.2))
}
