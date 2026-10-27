import SwiftUI
import UniformTypeIdentifiers

/// Staff load a sale's catalog from a spreadsheet saved as CSV: pick the file, check what was found,
/// then import. Hips already in the sale get the spreadsheet's catalog details; nothing staff entered
/// in the app (vet reports, opinions, media) is touched.
struct ImportSheet: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var catalog: CatalogImport?
    @State private var fileName = ""
    @State private var problem: String?
    @State private var importing = false
    @State private var done: (added: Int, updated: Int)?
    @State private var templateURL: URL?

    private var existing: Set<Int> { Set(store.hips.map(\.number)) }

    var body: some View {
        NavigationStack {
            Form {
                if let done {
                    Section {
                        Label("Imported into \(store.sale.name)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                        LabeledContent("New hips", value: "\(done.added)")
                        LabeledContent("Hips updated", value: "\(done.updated)")
                    }
                } else {
                    chooseSection
                    if let catalog { preview(catalog) }
                    if let problem {
                        Section { Text(problem).foregroundStyle(Theme.red) }
                    }
                }
            }
            .navigationTitle("Import spreadsheet")
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
                        Button("Import") { Task { await run(catalog) } }
                    }
                }
            }
            .interactiveDismissDisabled(importing)
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { result in
                switch result {
                case .success(let url): read(url)
                case .failure(let error): problem = error.localizedDescription
                }
            }
            .task { templateURL = writeTemplate() }
        }
    }

    private var chooseSection: some View {
        Section {
            Button {
                picking = true
            } label: {
                Label(catalog == nil ? "Choose spreadsheet (CSV)" : "Choose a different file", systemImage: "tablecells")
            }
            if let templateURL {
                ShareLink(item: templateURL) {
                    Label("Get the template", systemImage: "square.and.arrow.down")
                }
            }
        } header: {
            Text("Catalog for \(store.sale.name)")
        } footer: {
            Text("Needs columns for the hip number, sire and dam; name, sex, color, foaled, session, barn, consignor, the pedigree, reserve and C/P grades are optional. In Excel or Numbers, save or export the spreadsheet as CSV, then put it in Files, iCloud Drive or an email to yourself.")
        }
    }

    private func preview(_ catalog: CatalogImport) -> some View {
        let new = catalog.rows.filter { !existing.contains($0.number) }.count
        let update = catalog.rows.count - new
        let numbers = catalog.rows.map(\.number)
        return Group {
            Section {
                LabeledContent("File", value: fileName)
                LabeledContent("Hips found", value: "\(catalog.rows.count)")
                if let low = numbers.min(), let high = numbers.max() {
                    LabeledContent("Hip numbers", value: low == high ? "\(low)" : "\(low) to \(high)")
                }
                LabeledContent("New to this sale", value: "\(new)")
                if update > 0 { LabeledContent("Already here, will be updated", value: "\(update)") }
            } header: {
                Text("Check before importing")
            } footer: {
                Text(update > 0
                     ? "Hips already in this sale get the spreadsheet’s catalog details. Blank reserve, grade and link cells leave what’s there; vet reports, opinions and media aren’t touched."
                     : "Tap Import to add these hips to \(store.sale.name).")
            }
            if let first = catalog.rows.first {
                Section("First hip") {
                    LabeledContent("Hip", value: "\(first.number)")
                    if let name = first.name, !name.isEmpty { LabeledContent("Name", value: name) }
                    LabeledContent("By", value: [first.sire, first.dam].compactMap { $0 }.joined(separator: " — "))
                    if let sex = first.sex { LabeledContent("Sex", value: sex.capitalized) }
                    if let consignor = first.consignor, !consignor.isEmpty { LabeledContent("Consignor", value: consignor) }
                }
            }
            if !catalog.warnings.isEmpty || !catalog.ignoredColumns.isEmpty {
                Section("Notes") {
                    ForEach(catalog.warnings.prefix(8), id: \.self) { Text($0).font(.footnote) }
                    if catalog.warnings.count > 8 {
                        Text("…and \(catalog.warnings.count - 8) more.").font(.footnote).foregroundStyle(Theme.slate)
                    }
                    if !catalog.ignoredColumns.isEmpty {
                        Text("Not used: \(catalog.ignoredColumns.joined(separator: ", ")).")
                            .font(.footnote).foregroundStyle(Theme.slate)
                    }
                }
            }
        }
    }

    private func read(_ url: URL) {
        problem = nil
        catalog = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            catalog = try CatalogImport.read(data)
            fileName = url.lastPathComponent
        } catch {
            problem = error.localizedDescription
        }
    }

    private func run(_ catalog: CatalogImport) async {
        importing = true
        problem = nil
        done = await store.importCatalog(catalog)
        if done == nil { problem = store.errorMessage ?? "The import didn’t finish. Try again." }
        importing = false
    }

    private func writeTemplate() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Backring Buyer hips template.csv")
        do {
            try CatalogImport.template.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
