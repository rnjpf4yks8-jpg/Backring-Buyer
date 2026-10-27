import SwiftUI

/// Administrator: loads a Fasig-Tipton sale straight from fasigtipton.com: catalog, walk videos, photos,
/// catalog pages and outs. Paste the sale's catalogue link (or its code), check what was found, import.
/// Running it again for the same sale picks up new videos, photos and outs.
struct FasigImportSheet: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Import into this sale (from inside a sale). Nil: find the matching sale or make a new one.
    var into: Sale? = nil
    /// Called with the sale's ID when the administrator taps Open sale.
    var open: ((String) -> Void)? = nil

    @State private var link = ""
    @State private var looking = false
    @State private var catalog: FasigTipton.Catalog?
    @State private var problem: String?
    @State private var feature = true
    @State private var importing = false
    @State private var done: SaleStore.FasigResult?

    private var target: Sale? { into ?? catalog.flatMap(store.appSale(for:)) }

    var body: some View {
        NavigationStack {
            Form {
                if let done {
                    finished(done)
                } else {
                    linkSection
                    if let catalog { found(catalog) }
                    if let problem {
                        Section { Text(problem).foregroundStyle(Theme.red) }
                    }
                }
            }
            .navigationTitle(into?.fasigSale == nil ? "Import from Fasig-Tipton" : "Update from Fasig-Tipton")
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
            .task {
                // From inside a sale that came from Fasig-Tipton: look it up straight away.
                if let code = into?.fasigSale, catalog == nil {
                    link = code
                    await lookUp()
                }
            }
        }
    }

    private var linkSection: some View {
        Section {
            TextField("https://www.fasigtipton.com/2026/…", text: $link, axis: .vertical)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...3)
            if UIPasteboard.general.hasStrings {
                Button {
                    link = UIPasteboard.general.string ?? ""
                    Task { await lookUp() }
                } label: {
                    Label("Paste link and look up", systemImage: "doc.on.clipboard")
                }
            }
            if looking {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the catalog from fasigtipton.com…").foregroundStyle(Theme.slate)
                }
            } else {
                Button {
                    Task { await lookUp() }
                } label: {
                    Label("Look up", systemImage: "magnifyingglass")
                }
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Fasig-Tipton sale")
        } footer: {
            Text("In Safari, open the sale’s catalogue page on fasigtipton.com, tap Share → Copy, and paste it here. The sale code (like M26B) works too.")
        }
    }

    @ViewBuilder
    private func found(_ catalog: FasigTipton.Catalog) -> some View {
        Section {
            LabeledContent("Sale", value: catalog.name)
            if let day = catalog.day { LabeledContent("Date", value: Sale.dateText(day)) }
            LabeledContent("Hips", value: catalog.hipRange.map { "\(catalog.horses.count) (\($0.lowerBound)–\($0.upperBound))" }
                           ?? "\(catalog.horses.count)")
            LabeledContent("Walk videos", value: "\(catalog.videoCount)")
            LabeledContent("Photos", value: "\(catalog.photoCount)")
            LabeledContent("Out", value: "\(catalog.outCount)")
            if catalog.unreadable > 0 {
                Text("\(catalog.unreadable) hip(s) couldn’t be read and will be skipped.")
                    .font(.footnote).foregroundStyle(Theme.red)
            }
        } header: {
            Text("Found on fasigtipton.com")
        }
        Section {
            if let target {
                LabeledContent("Goes into", value: target.name)
            } else {
                LabeledContent("Goes into", value: "A new sale")
            }
            if target?.id != store.featuredSaleID || target == nil {
                Toggle("Feature this sale (NOW)", isOn: $feature)
            }
        } footer: {
            Text(target == nil
                 ? "Each hip gets its catalog details, catalog page, walk video and photo, and outs are marked OUT."
                 : "New hips are added; hips already there get Fasig-Tipton’s latest details, videos, photos and outs. Videos, pictures, grades, vet reports and opinions your staff added are kept.")
        }
    }

    @ViewBuilder
    private func finished(_ result: SaleStore.FasigResult) -> some View {
        Section {
            Label("Imported into \(result.saleName)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.green)
            LabeledContent("New hips", value: "\(result.added)")
            LabeledContent("Hips updated", value: "\(result.updated)")
        }
        if let open, into == nil {
            Section {
                Button {
                    dismiss()
                    open(result.saleID)
                } label: {
                    Label("Open \(result.saleName)", systemImage: "arrow.right.circle")
                }
            }
        }
    }

    private func lookUp() async {
        looking = true
        problem = nil
        catalog = nil
        defer { looking = false }
        do {
            let found = try await FasigTipton.lookUp(link)
            catalog = found
            let goesInto = into ?? store.appSale(for: found)
            feature = goesInto == nil || goesInto?.id == store.featuredSaleID
        } catch {
            problem = error.localizedDescription
        }
    }

    private func run(_ catalog: FasigTipton.Catalog) async {
        importing = true
        problem = nil
        store.errorMessage = nil
        done = await store.importFasigTipton(catalog, into: into, feature: feature && target?.id != store.featuredSaleID)
        if done == nil { problem = store.errorMessage ?? "The import didn’t finish. Try again." }
        importing = false
    }
}
