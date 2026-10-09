//
//  EmergencyBanner.swift
//  RescueSight
//
//  Always at the top of the report form: RescueSight supports emergency
//  services, it does not replace 911.
//

import SwiftUI

struct EmergencyBanner: View {
    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Image(systemName: "phone.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color(.systemRed), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("In an emergency, call 911 first.")
                    .font(.headline)
                Text("RescueSight shares reports with responders, but it is not a 911 service.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            // On an iPhone this opens the phone app (iOS asks before calling).
            Link(destination: URL(string: "tel:911")!) {
                Text("Call")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Spacing.m)
                    .frame(minHeight: minimumTapSize)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(.systemRed))
            .accessibilityLabel("Call 911")
        }
        .padding(Spacing.m)
        .background(Color(.systemRed).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    EmergencyBanner().padding()
}
