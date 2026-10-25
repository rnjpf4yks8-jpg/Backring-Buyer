import SwiftUI

/// Staff pick who gives each paid opinion for the open sale: two vets and two bloodstock agents.
/// Only the person in a slot can post that slot's opinion.
struct PanelSheet: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var panel: [String: PanelMember] = [:]
    @State private var saving = false

    private let slots: [(slot: OpinionSlot, title: String, orgLabel: String)] = [
        (.vet1, "Vet 1", "Practice"),
        (.vet2, "Vet 2", "Practice"),
        (.bs1, "BS1", "Agency"),
        (.bs2, "BS2", "Agency"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                ForEach(slots, id: \.slot) { entry in
                    Section {
                        Picker("Person", selection: person(entry.slot)) {
                            Text("Nobody yet").tag(String?.none)
                            ForEach(store.people, id: \.uid) { person in
                                Text(label(person)).tag(Optional(person.uid))
                            }
                        }
                        if panel[entry.slot.rawValue] != nil {
                            TextField(entry.orgLabel, text: org(entry.slot))
                        }
                    } header: {
                        Text(entry.title)
                    }
                }
                Section {
                } footer: {
                    Text("Vets and agents need to create an account in the app first. Then they appear in these lists. A buyer you pick here becomes a vet or agent.")
                }
            }
            .navigationTitle("Panel · \(store.sale.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                saving = true
                                if await store.savePanel(panel) { dismiss() }
                                saving = false
                            }
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) { ErrorBanner() }
            .task {
                panel = store.sale.panel
                await store.loadPeople()
            }
        }
    }

    private func label(_ person: AppUser) -> String {
        [person.name, person.email, person.role == .buyer ? nil : person.role.label]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func person(_ slot: OpinionSlot) -> Binding<String?> {
        Binding(
            get: { panel[slot.rawValue]?.uid },
            set: { uid in
                guard let uid, let person = store.people.first(where: { $0.uid == uid }) else {
                    panel[slot.rawValue] = nil
                    return
                }
                let org = panel[slot.rawValue]?.org ?? ""
                panel[slot.rawValue] = PanelMember(uid: uid, name: person.name, org: org)
            }
        )
    }

    private func org(_ slot: OpinionSlot) -> Binding<String> {
        Binding(
            get: { panel[slot.rawValue]?.org ?? "" },
            set: { panel[slot.rawValue]?.org = $0 }
        )
    }
}
