import SwiftUI

/// Staff add a sale (the + button on the sales list) or change one's name, company and date
/// (press and hold a sale). Does what `node admin.js create-sale` does.
struct SaleSheet: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The sale being changed, or nil to add a new one.
    let editing: Sale?
    @State private var name = ""
    @State private var company = ""
    @State private var day = Date()
    @State private var feature = true
    @State private var triedSaving = false
    @State private var saving = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedCompany: String { company.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isFeatured: Bool { editing != nil && editing?.id == store.featuredSaleID }

    /// The ID a new sale gets (also usable with admin.js on a computer).
    private var newID: String {
        Sale.makeID(company: trimmedCompany, day: day, taken: Set(store.sales.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Sale name, e.g. October Yearling Sale", text: $name)
                        .textInputAutocapitalization(.words)
                    if triedSaving && trimmedName.isEmpty {
                        Text("Enter the sale’s name.").font(Theme.sans(14)).foregroundStyle(Theme.red)
                    }
                    TextField("Company, e.g. Fasig-Tipton", text: $company)
                        .textInputAutocapitalization(.words)
                    if triedSaving && trimmedCompany.isEmpty {
                        Text("Enter the sale company.").font(Theme.sans(14)).foregroundStyle(Theme.red)
                    }
                    DatePicker("Date", selection: $day, displayedComponents: .date)
                } header: {
                    Text("Sale")
                } footer: {
                    Text(editing.map { "Sale ID \($0.id). The panel, prices and hips stay as they are." }
                         ?? "Sale ID \(newID). After adding it, open the sale and tap + → Import spreadsheet to load the catalog.")
                }

                Section {
                    if isFeatured {
                        Label("This is the featured sale (NOW).", systemImage: "star.fill")
                            .foregroundStyle(Theme.ink)
                    } else {
                        Toggle("Feature this sale", isOn: $feature)
                    }
                } footer: {
                    Text("The featured sale is marked NOW on the sales list. Featuring this one takes NOW off the other.")
                }

                if editing == nil {
                    Section {
                    } footer: {
                        Text("Opinion prices start at \(usd(25)) per vet and \(usd(50)) per bloodstock agent. Add the vets and agents on the sale’s Panel screen, and hips with + inside the sale.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add sale" : "Edit sale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button(editing == nil ? "Add" : "Save") { save() }
                    }
                }
            }
            .overlay(alignment: .bottom) { ErrorBanner() }
            .onAppear {
                store.errorMessage = nil
                guard let editing else { return }
                name = editing.name
                company = editing.company
                day = editing.day ?? Date()
                feature = false
            }
        }
    }

    private func save() {
        triedSaving = true
        guard !trimmedName.isEmpty, !trimmedCompany.isEmpty else { return }
        var sale = editing ?? Sale(id: newID, name: "", company: "", date: "")
        sale.name = trimmedName
        sale.company = trimmedCompany
        sale.date = Sale.dateText(day)
        Task {
            saving = true
            if await store.save(sale, feature: feature && !isFeatured) { dismiss() }
            saving = false
        }
    }
}
