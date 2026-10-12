//
//  RoleButton.swift
//  RollCall
//
//  The small pill in the top corner showing who you are acting as. Tapping
//  it lets you switch roles (this is a demo with no real accounts).
//

import SwiftUI

struct RoleButton: View {
    @Environment(AppSession.self) private var session
    let name: String

    var body: some View {
        Menu {
            if let role = session.role {
                Text("Acting as \(name)")
                Text(role.title)
            }
            Divider()
            Button("Switch role", systemImage: "arrow.left.arrow.right") { session.switchRole() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: session.role?.symbol ?? "person.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor, in: Circle())
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            .padding(.trailing, Spacing.s)
            .frame(minHeight: 34)
        }
        .accessibilityLabel("Acting as \(name)")
        .accessibilityHint("Opens a menu to switch roles")
        .accessibilityIdentifier("roleButton")
    }
}
