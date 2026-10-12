//
//  AccountButton.swift
//  RollCall
//
//  The small pill in the top corner of the Roll Call and Community tabs:
//  who's signed in, and "Sign out".
//

import SwiftUI

struct AccountButton: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.brand) private var brand

    var body: some View {
        if let me = auth.me {
            Menu {
                Text(me.name)
                Text(me.email)
                Divider()
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await auth.signOut() }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(initials(me.name))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(brand, in: Circle())
                    Text(me.firstName)
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
            .accessibilityLabel("Account: \(me.name)")
            .accessibilityHint("Opens a menu with Sign out")
            .accessibilityIdentifier("accountButton")
        }
    }
}

func initials(_ name: String) -> String {
    name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
}
