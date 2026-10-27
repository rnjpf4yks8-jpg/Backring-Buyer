import SwiftUI

/// Staff load a sale's catalog straight from fasigtipton.com: the app finds the sale's page from its
/// name (or staff paste the link), shows what it found, then imports it like a spreadsheet. Hips
/// already in the sale get the catalog details; vet reports, opinions, grades and reserves stay.
struct FasigTiptonSheet: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var loading = false
    @State private var catalog: FasigTipton.Catalog?
    @State private var includeOuts = false
    @State private var problem: String?
    @State private var importing = false
    @State private var done: (added: Int, updated: Int)?

    private var existing: Set<Int> { Set(store.hips.map(\.number)) }
    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                if let done {
                    Section {
                        Label("Loaded into \(store.sale.name)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                        LabeledContent("New hips", value: "\(done.added)")
                        LabeledContent("Hips updated", value: "\(done.updated)")
                    } footer: {
                        Text("Each hip’s Pedigree button opens its Fasig-Tipton catalog page. Load again any time to pick up new photos and walk videos.")
                    }
                } else {
                    Section {
                        TextField("https://www.fasigtipton.com/2026/…", text: $link, axis: .vertical)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            Task { await find() }
                        } label: {
                            if loading {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Reading fasigtipton.com…").foregroundStyle(Theme.slate)
                                }
                            } else {
                                Label(catalog == nil ? "Find the catalog" : "Find again", systemImage: "magnifyingglass")
                            }
                        }
                        .disabled(loading || importing || trimmedLink.isEmpty)
                    } header: {
                        Text("Sale page on fasigtipton.com")
                    } footer: {
                        Text("Worked out from the sale’s name. If it isn’t found, open the sale on fasigtipton.com, copy the link from the address bar and paste it here.")
                    }
                    if let catalog { preview(catalog) }
                    if let problem {
                        Section { Text(problem).foregroundStyle(Theme.red) }
                    }
                }
            }
            .navigationTitle("Load from Fasig-Tipton")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if done == nil { Button("Cancel") { dismiss() }.disabled(importing) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if done != nil {
                        Button("Done") { dismiss() }
                    } else if importing {
                        ProgressView()
                    } else if let catalog {
                        Button("Load") { Task { await run(catalog) } }
                    }
                }
            }
            .interactiveDismissDisabled(importing)
            .task {
                guard link.isEmpty else { return }
                let year = store.sale.day.map { Calendar(identifier: .gregorian).component(.year, from: $0) }
                link = FasigTipton.guessPage(saleName: store.sale.name, year: year)
                await find()
            }
        }
    }

    private func preview(_ catalog: FasigTipton.Catalog) -> some View {
        let rows = catalog.rows(includingOuts: includeOuts)
        let new = rows.filter { !existing.contains($0.number) }.count
        let update = rows.count - new
        let numbers = rows.map(\.number)
        return Group {
            Section {
                LabeledContent("Sale", value: catalog.title)
                LabeledContent("Starts", value: Self.dayText(catalog.sale.saleStartDay))
                LabeledContent("Hips", value: "\(rows.count)")
                if let low = numbers.min(), let high = numbers.max() {
                    LabeledContent("Hip numbers", value: low == high ? "\(low)" : "\(low) to \(high)")
                }
                LabeledContent("With a sale photo", value: "\(rows.filter { $0.photoURL != nil }.count)")
                LabeledContent("With a walk video", value: "\(rows.filter { $0.walkVideoURL != nil }.count)")
                LabeledContent("New to this sale", value: "\(new)")
                if update > 0 { LabeledContent("Already here, will be updated", value: "\(update)") }
                if !catalog.outs.isEmpty {
                    Toggle("Include the \(catalog.outs.count) outs", isOn: $includeOuts)
                }
            } header: {
                Text("Found on fasigtipton.com")
            } footer: {
                Text(catalog.outs.isEmpty
                     ? "Tap Load to bring these hips into \(store.sale.name)."
                     : "Outs are horses withdrawn from the sale (hips \(Self.list(catalog.outs))). They’re left off unless you include them.")
            }
            if let first = rows.first {
                Section("First hip") {
                    LabeledContent("Hip", value: "\(first.number)")
                    if let name = first.name, !name.isEmpty { LabeledContent("Name", value: name) }
                    LabeledContent("By", value: [first.sire, first.dam].compactMap { $0 }.joined(separator: " — "))
                    if let sex = first.sex { LabeledContent("Sex", value: sex.capitalized) }
                    if let foaled = first.foaled, !foaled.isEmpty { LabeledContent("Foaled", value: foaled) }
                    if let consignor = first.consignor, !consignor.isEmpty { LabeledContent("Consignor", value: consignor) }
                }
            }
        }
    }

    private func find() async {
        guard !trimmedLink.isEmpty else { return }
        loading = true
        problem = nil
        defer { loading = false }
        do {
            catalog = try await FasigTipton.load(trimmedLink)
        } catch {
            catalog = nil
            problem = error.localizedDescription
        }
    }

    private func run(_ catalog: FasigTipton.Catalog) async {
        importing = true
        problem = nil
        let rows = catalog.rows(includingOuts: includeOuts)
        done = await store.importCatalog(CatalogImport(rows: rows, warnings: [], ignoredColumns: []))
        if done == nil { problem = store.errorMessage ?? "Loading didn’t finish. Try again." }
        importing = false
    }

    /// "2026-10-27" → "Oct 27, 2026".
    private static func dayText(_ day: String) -> String {
        let reader = DateFormatter()
        reader.locale = Locale(identifier: "en_US_POSIX")
        reader.dateFormat = "yyyy-MM-dd"
        guard let date = reader.date(from: day) else { return day }
        return Sale.dateText(date)
    }

    /// "3, 12, 16 and 31 more".
    private static func list(_ hips: [Int]) -> String {
        let shown = hips.prefix(8).map(String.init).joined(separator: ", ")
        return hips.count > 8 ? "\(shown) and \(hips.count - 8) more" : shown
    }
}
