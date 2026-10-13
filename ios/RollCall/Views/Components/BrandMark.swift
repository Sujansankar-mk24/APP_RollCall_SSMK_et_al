//
//  BrandMark.swift
//  RollCall
//
//  The RollCall logo mark: a check mark on an ink square, like a box ticked
//  on a roll-call sheet, with the sheet's ruled lines beside it.
//

import SwiftUI

struct BrandMark: View {
    @Environment(\.brand) private var brand
    var size: CGFloat = 88
    var showsLines = true

    var body: some View {
        HStack(alignment: .center, spacing: size * 0.18) {
            ZStack {
                Rectangle().fill(brand)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .black))
                    .foregroundStyle(Color.paper)
            }
            .frame(width: size, height: size)
            if showsLines {
                // Three ruled lines, like names waiting on the sheet.
                VStack(alignment: .leading, spacing: size * 0.16) {
                    ForEach([1.0, 0.75, 0.9], id: \.self) { width in
                        Rectangle().fill(brand.opacity(0.35)).frame(width: size * width, height: size * 0.09)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    BrandMark().padding(40).sheetPage()
}
