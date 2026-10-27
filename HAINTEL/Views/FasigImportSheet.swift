import SwiftUI

/// Administrator: loads a Fasig-Tipton sale straight from fasigtipton.com: catalog, walk videos, photos,
/// catalog pages and outs. Pick the sale from Fasig-Tipton's list (or paste its link or code), check
/// what was found, import.
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
    @State private var catalogues: [FasigTipton.Catalogue] = []
    @State private var loadingList = false
    @State private var listProblem: String?
    @State private var picked: FasigTipton.Catalogue?

    /// Updating a sale that already came from Fasig-Tipton: no need to pick it again.
    private var updating: Bool { into?.fasigSale != nil }

    private var target: Sale? { into ?? catalog.flatMap(store.appSale(for:)) }

    var body: some View {
        NavigationStack {
            Form {
                if let done {
                    finished(done)
                } else if let catalog {
                    found(catalog)
                    if !updating {
                        Section {
                            Button {
                                self.catalog = nil
                                picked = nil
                                problem = nil
                            } label: {
                                Label("Choose a different sale", systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
                } else {
                    if !updating { salesSection }
                    linkSection
                }
                if done == nil, let problem {
                    Section { Text(problem).foregroundStyle(Theme.red) }
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
                } else if catalogues.isEmpty {
                    await loadList()
                }
            }
        }
    }

    /// Fasig-Tipton's sales, newest first. Tapping one looks it up.
    private var salesSection: some View {
        Section {
            if loadingList {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading Fasig-Tipton’s sales…").foregroundStyle(Theme.slate)
                }
            }
            ForEach(catalogues) { sale in
                Button {
                    Task { await pick(sale) }
                } label: {
                    CatalogueRow(sale: sale, busy: looking && picked == sale)
                }
                .disabled(looking)
            }
            if let listProblem {
                Text(listProblem).foregroundStyle(Theme.red)
                Button("Try again") { Task { await loadList() } }
            }
        } header: {
            Text("Pick a Fasig-Tipton sale")
        } footer: {
            Text("Newest first, as listed on fasigtipton.com.")
        }
    }

    private var linkSection: some View {
        Section {
            TextField("Paste a sale link, or a code like M26B", text: $link, axis: .vertical)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...3)
                .onSubmit { Task { await lookUp() } }
            if UIPasteboard.general.hasStrings {
                Button {
                    link = UIPasteboard.general.string ?? ""
                    Task { await lookUp() }
                } label: {
                    Label("Paste and look up", systemImage: "doc.on.clipboard")
                }
            }
            if looking && picked == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the catalog from fasigtipton.com…").foregroundStyle(Theme.slate)
                }
            } else {
                Button {
                    picked = nil
                    Task { await lookUp() }
                } label: {
                    Label("Look up", systemImage: "magnifyingglass")
                }
                .disabled(looking || link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Link(destination: URL(string: "https://www.fasigtipton.com/catalogues")!) {
                Label("Open fasigtipton.com in Safari", systemImage: "safari")
            }
        } header: {
            Text(updating ? "Fasig-Tipton sale" : "Or paste a link")
        } footer: {
            Text("On fasigtipton.com, open the sale’s catalogue page, tap Share → Copy, then come back and tap Paste and look up.")
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

    private func pick(_ sale: FasigTipton.Catalogue) async {
        picked = sale
        link = sale.url.absoluteString
        await lookUp()
    }

    private func loadList() async {
        loadingList = true
        listProblem = nil
        defer { loadingList = false }
        do {
            catalogues = try await FasigTipton.catalogueList()
            if catalogues.isEmpty { listProblem = "Couldn’t find Fasig-Tipton’s sale list. Paste the sale’s link below instead." }
        } catch {
            listProblem = "Couldn’t load Fasig-Tipton’s sales (\(error.localizedDescription)) Paste the sale’s link below instead."
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

/// A sale in Fasig-Tipton's list: its catalogue cover, name, dates and place.
private struct CatalogueRow: View {
    let sale: FasigTipton.Catalogue
    let busy: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: sale.cover) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Theme.mist
            }
            .frame(width: 34, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(sale.name).foregroundStyle(Theme.ink)
                Text([sale.dates, sale.location].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Theme.slate)
            }
            Spacer(minLength: 8)
            if busy {
                ProgressView()
            } else {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.slate)
            }
        }
    }
}
