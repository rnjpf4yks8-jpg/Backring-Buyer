import SwiftUI
import UniformTypeIdentifiers

/// The condition books loaded so far. Every horse's Best races tab uses their races.
struct BooksView: View {
    @Environment(StableStore.self) private var store
    @State private var adding = false
    @State private var removing: ConditionBook?

    private var books: [ConditionBook] {
        store.books.sorted { a, b in
            let ta = a.trackName ?? a.track, tb = b.trackName ?? b.track
            if ta != tb { return ta < tb }
            return (a.from ?? "") < (b.from ?? "")
        }
    }

    var body: some View {
        List {
            Section {
                Text("Download a track's condition book PDF from its website (racing office or horsemen's page), then add it here. Claude reads every race in it: date, type, claiming price, purse, who's eligible, distance and surface.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Button { adding = true } label: { Label("Add condition book PDF", systemImage: "plus") }
                    .buttonStyle(ActionButtonStyle(primary: true))
            }
            Section("Loaded") {
                if books.isEmpty {
                    Text("No condition books yet.").foregroundStyle(Theme.muted)
                }
                ForEach(books) { book in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(book.trackName ?? Track.find(book.track)?.name ?? book.track) · \(book.title ?? "Condition book")")
                            .font(.headline)
                        Text(detail(book)).font(.footnote).foregroundStyle(Theme.muted)
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { removing = book }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .navigationTitle("Condition books")
        .sheet(isPresented: $adding) { BookImportSheet() }
        .confirmationDialog("Remove this condition book?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        ), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                guard let book = removing else { return }
                Task {
                    do { try await store.delete(book) } catch { store.show(error) }
                }
            }
        } message: {
            Text("Its races come off every horse's Best races list.")
        }
    }

    private func detail(_ book: ConditionBook) -> String {
        var parts = ["\(book.races.count) races"]
        if let from = book.from {
            parts.append(Dates.nice(from) + (book.to.map { " – " + Dates.nice($0) } ?? ""))
        }
        if let loaded = book.loadedAt { parts.append("added \(loaded.prefix(10))") }
        return parts.joined(separator: " · ")
    }
}

/// Pick a track and its condition book PDF; Claude reads it five pages at a time.
struct BookImportSheet: View {
    @Environment(StableStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var track = "DED"
    @State private var title = ""
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var file: ChartFile?
    @State private var picking = false
    @State private var working = false
    @State private var status: String?
    @State private var good = false
    @State private var done = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Track", selection: $track) {
                        ForEach(Track.byName) { t in Text("\(t.name) (\(t.state))").tag(t.code) }
                    }
                    TextField("Book name (e.g. Book 1, Nov 13 – Dec 13)", text: $title)
                    Stepper("Year of the races: \(String(year))", value: $year, in: 2024...2035)
                }
                Section {
                    Button {
                        picking = true
                    } label: {
                        Label(file?.name ?? "Choose the condition book PDF", systemImage: "doc.richtext")
                    }
                } footer: {
                    Text("A 100-page book takes several minutes. Keep this screen open until it says the races were added.")
                }
                if let status {
                    Section { Text(status).foregroundStyle(good ? Theme.good : working ? Theme.ink : Theme.bad) }
                }
            }
            .navigationTitle("Add a condition book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(done ? "Done" : "Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else if !done {
                        Button("Read the book") { Task { await read() } }.disabled(file == nil)
                    }
                }
            }
            .interactiveDismissDisabled(working)
            .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        file = ChartFile(name: url.lastPathComponent, data: data)
                        if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
                    } else {
                        status = "Couldn’t open that file."
                    }
                case .failure(let error):
                    status = error.localizedDescription
                }
            }
        }
    }

    private func read() async {
        guard let file, let t = Track.find(track) else { return }
        working = true
        good = false
        status = "Opening the PDF…"
        defer { working = false }
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty ? file.name : title.trimmingCharacters(in: .whitespaces)
        do {
            let book = try await store.readBook(pdf: file.data, fileName: file.name, track: t, title: name, year: year) { p in
                Task { @MainActor in
                    status = "Read \(p.done) of \(p.total) parts · \(p.races) races so far"
                        + (p.failed > 0 ? " · \(p.failed) part\(p.failed == 1 ? "" : "s") couldn’t be read" : "")
                }
            }
            good = true
            done = true
            status = "\(t.name): \(book.races.count) races added."
        } catch {
            status = error.localizedDescription
        }
    }
}
