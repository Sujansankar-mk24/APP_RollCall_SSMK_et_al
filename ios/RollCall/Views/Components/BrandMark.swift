//
//  BrandMark.swift
//  RollCall
//
//  A placeholder for the RollCall logo (the real one isn't designed yet): a
//  check mark inside a ring, like a name checked off on a roll call. Swap
//  in the real logo here and it updates everywhere.
//

import SwiftUI

struct BrandMark: View {
    @Environment(\.brand) private var brand
    var size: CGFloat = 88
    /// Not used anymore. Kept so older calls still work.
    var showsLines = true

    var body: some View {
        ZStack {
            Circle().strokeBorder(brand, lineWidth: max(2, size * 0.06))
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(brand)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    BrandMark().padding(40).sheetPage()
}
