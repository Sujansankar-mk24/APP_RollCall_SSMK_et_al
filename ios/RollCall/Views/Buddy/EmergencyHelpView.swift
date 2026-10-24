//
//  EmergencyHelpView.swift
//  RollCall
//
//  "They need help": for when you check on your buddy and they're hurt or
//  not okay. A big Call 911 button, and everything the dispatcher will ask
//  for on one screen, so you can read it out instead of remembering it in a
//  panic: the address, who lives there, medical equipment, how they get
//  around, their language, and who else to call.
//
//  RollCall doesn't call 911 by itself. The phone's own call screen opens,
//  and you talk to the dispatcher as usual.
//

import SwiftUI

struct EmergencyHelpView: View {
    let name: String
    let address: String?
    /// Short facts for the dispatcher: "2 people (1 over 65)", "Oxygen concentrator".
    let facts: [String]
    let emergencyContact: (name: String, phone: String)?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Emergency").sheetLabelStyle().foregroundStyle(Color(.systemRed))
                        Text("\(name) needs help").font(.sheetDisplay)
                    }

                    Button { call("911") } label: {
                        Label("Call 911", systemImage: "phone.fill")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .foregroundStyle(.white)
                            .background(Color(.systemRed), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("call911")

                    if address != nil || !facts.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionLabel("Tell the dispatcher")
                        SheetCard {
                            if let address {
                                fact("mappin.and.ellipse", address, emphasized: true)
                            }
                            ForEach(facts, id: \.self) { fact("info.circle", $0) }
                        }
                        .accessibilityIdentifier("dispatcherFacts")
                    }
                    }

                    if let contact = emergencyContact {
                        Button { call(contact.phone) } label: {
                            HStack(spacing: Spacing.m) {
                                Image(systemName: "person.crop.circle.badge.exclamationmark").font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Call their emergency contact").font(.headline)
                                    Text(verbatim: "\(contact.name) · \(contact.phone)").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "phone.fill")
                            }
                            .sheetBox(padding: Spacing.l)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    SheetNote(text: "Stay with them if it's safe. Don't move someone who may be badly hurt unless they're in danger where they are.",
                              systemImage: "heart.text.square")
                }
                .padding(Spacing.l)
            }
            .sheetPage()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }.flat()
            }
        }
    }

    private func fact(_ symbol: String, _ text: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24)
            Text(verbatim: text)
                .font(emphasized ? .headline : .body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .sheetRow()
    }

    private func call(_ number: String) {
        let digits = number.filter(\.isNumber)
        if let url = URL(string: "tel:\(digits)") { openURL(url) }
    }
}

extension Household {
    /// What a 911 dispatcher needs to know about this household, in plain words.
    var dispatcherFacts: [String] {
        var facts: [String] = []
        if people == 1 {
            facts.append(seniors > 0 ? String(localized: "Lives alone, over 65")
                         : children > 0 ? String(localized: "Lives alone, under 18") : String(localized: "Lives alone"))
        } else {
            var ages: [String] = []
            if seniors > 0 { ages.append(String(localized: "\(seniors) over 65")) }
            if children > 0 { ages.append(String(localized: "\(children) under 18")) }
            facts.append(ages.isEmpty ? String(localized: "\(people) people live here")
                         : String(localized: "\(people) people live here (\(ages.joined(separator: ", ")))"))
        }
        for item in medicalEquipment { facts.append(String(localized: "Uses \(String(localized: item.title).lowercased())")) }
        if mobilityNeeds { facts.append(String(localized: "Has trouble walking or with stairs")) }
        if noVehicle { facts.append(String(localized: "Has no car")) }
        if language == .es { facts.append(String(localized: "Speaks Spanish")) }
        if pets { facts.append(String(localized: "Has pets")) }
        if !notes.trimmingCharacters(in: .whitespaces).isEmpty { facts.append(notes) }
        return facts
    }
}
