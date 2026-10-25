import SwiftUI

/// Staff only: vets, agents and staff who signed up and are waiting for HAINTEL to approve them.
/// Each shows the role they asked for, which staff can change before approving.
struct AccountsSheet: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.pendingAccounts.isEmpty {
                        Text("Nobody waiting. When a vet, agent or staff member creates an account, it shows up here.")
                            .font(Theme.sans(15)).foregroundStyle(Theme.slate)
                    }
                    ForEach(store.pendingAccounts, id: \.uid) { person in
                        PendingAccountRow(person: person)
                    }
                } header: {
                    Text("Waiting for approval")
                }

                let rejected = store.people.filter { $0.accountStatus == .rejected }
                if !rejected.isEmpty {
                    Section {
                        ForEach(rejected, id: \.uid) { person in
                            PendingAccountRow(person: person)
                        }
                    } header: {
                        Text("Not approved")
                    } footer: {
                        Text("These accounts can browse the free catalog only. Approve one here if you change your mind.")
                    }
                }
            }
            .navigationTitle("New accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .overlay(alignment: .bottom) { ErrorBanner() }
            .refreshable { await store.loadPeople() }
            .task { await store.loadPeople() }
        }
    }
}

private struct PendingAccountRow: View {
    @Environment(SaleStore.self) private var store
    let person: AppUser
    @State private var role: Role = .buyer
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink)
                if let email = person.email, !email.isEmpty {
                    Text(email).font(Theme.sans(14)).foregroundStyle(Theme.slate)
                }
                Text("Asked to be: \(person.role.label)").font(Theme.sans(14)).foregroundStyle(Theme.slate)
            }
            Picker("Approve as", selection: $role) {
                ForEach(Role.signUpChoices, id: \.self) { Text($0.label).tag($0) }
            }
            HStack(spacing: 12) {
                Button {
                    working = true
                    Task {
                        await store.approveAccount(person, as: role)
                        working = false
                    }
                } label: {
                    Text("Approve").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.blue)
                if person.accountStatus == .pending {
                    Button(role: .destructive) {
                        working = true
                        Task {
                            await store.rejectAccount(person)
                            working = false
                        }
                    } label: {
                        Text("Reject").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .disabled(working)
        }
        .padding(.vertical, 4)
        .onAppear { role = person.role }
    }
}
