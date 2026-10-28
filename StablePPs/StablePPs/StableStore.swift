import Foundation
import Observation
import PDFKit

/// A chart PDF picked in Files or shared from Safari.
struct ChartFile: Identifiable {
    let id = UUID()
    var name: String
    var data: Data
}

/// Charts waiting to be read, for one horse or for whichever of your horses are in them.
struct ChartBatch: Identifiable {
    let id = UUID()
    var files: [ChartFile]
    var horseID: String?
}

/// What happened to one chart.
struct ChartOutcome {
    var added: [String] = []        // "Authentic Queen: 12Oct26 DeD · 2nd · $4,000"
    var skipped: [String] = []      // "Guidon isn't in this chart."
}

/// App state: who's signed in, the horses, the open horse's race lines and the condition books.
@MainActor
@Observable
final class StableStore {
    enum Phase { case starting, signedOut, signedIn, notConfigured }

    var phase: Phase = .starting
    var email: String?
    var horses: [Horse] = []
    var horsesLoaded = false
    var books: [ConditionBook] = []
    /// Race lines of the horse that's open (`linesHorseID`).
    var lines: [RaceLine] = []
    var linesHorseID: String?
    var errorMessage: String?
    /// Chart PDFs shared into the app from Safari or Files, waiting for the import sheet.
    var incoming: ChartBatch?

    @ObservationIgnored private let backend: StableBackend?
    @ObservationIgnored private var stopAuth: (() -> Void)?
    @ObservationIgnored private var stopHorses: (() -> Void)?
    @ObservationIgnored private var stopBooks: (() -> Void)?
    @ObservationIgnored private var stopLines: (() -> Void)?
    @ObservationIgnored private var uid: String?

    init() {
        backend = StableBackend.makeIfConfigured()
        if backend == nil { phase = .notConfigured }
    }

    func start() {
        guard let backend, stopAuth == nil else { return }
        stopAuth = backend.watchAuth { [weak self] uid, email in
            Task { @MainActor in self?.signedIn(uid: uid, email: email) }
        }
    }

    private func signedIn(uid: String?, email: String?) {
        guard uid != self.uid || phase == .starting else { return }
        self.uid = uid
        self.email = email
        stopHorses?(); stopBooks?(); stopLines?()
        stopHorses = nil; stopBooks = nil; stopLines = nil
        horses = []; books = []; lines = []; linesHorseID = nil; horsesLoaded = false
        guard let backend, uid != nil else {
            phase = .signedOut
            return
        }
        phase = .signedIn
        stopHorses = backend.watchHorses({ [weak self] list in
            Task { @MainActor in
                guard let self else { return }
                self.horses = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.horsesLoaded = true
                await self.addMissingEquibaseLinks()
            }
        }, onError: { [weak self] error in
            Task { @MainActor in self?.show(error) }
        })
        stopBooks = backend.watchBooks({ [weak self] list in
            Task { @MainActor in self?.books = list }
        }, onError: { _ in })
    }

    func horse(_ id: String) -> Horse? {
        horses.first { $0.id == id }
    }

    /// Starts listening to one horse's race lines (the horse that's open).
    func watchLines(_ horseID: String) {
        guard let backend, linesHorseID != horseID else { return }
        stopLines?()
        lines = []
        linesHorseID = horseID
        stopLines = backend.watchLines(horseID: horseID, { [weak self] list in
            Task { @MainActor in
                guard self?.linesHorseID == horseID else { return }
                self?.lines = list
            }
        }, onError: { [weak self] error in
            Task { @MainActor in self?.show(error) }
        })
    }

    func lines(for horseID: String) -> [RaceLine] {
        linesHorseID == horseID ? Records.sorted(lines) : []
    }

    func show(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func requireBackend() throws -> StableBackend {
        guard let backend else { throw BackendError(message: "Firebase isn’t set up in this build.") }
        return backend
    }

    // MARK: Account

    func signIn(email: String, password: String) async throws {
        try await requireBackend().signIn(email: email, password: password)
    }

    func createAccount(email: String, password: String) async throws {
        try await requireBackend().createAccount(email: email, password: password)
    }

    func sendPasswordReset(email: String) async throws {
        try await requireBackend().sendPasswordReset(email: email)
    }

    func signOut() {
        do { try requireBackend().signOut() } catch { show(error) }
    }

    // MARK: Horses

    /// A document id from the name: "Told (IRE)" → "told", unique in this stable.
    func newHorseID(for name: String) -> String {
        var base = name.lowercased()
        if let paren = base.firstIndex(of: "(") { base = String(base[..<paren]) }
        base = base.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        while base.contains("--") { base = base.replacingOccurrences(of: "--", with: "-") }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.isEmpty { base = "horse" }
        var id = base, n = 2
        while horses.contains(where: { $0.id == id }) {
            id = "\(base)-\(n)"
            n += 1
        }
        return id
    }

    func save(_ horse: Horse) async throws {
        var h = horse
        h.updatedAt = Dates.stamp()
        if h.createdAt == nil { h.createdAt = h.updatedAt }
        if h.record == nil { h.record = Record() }
        try await requireBackend().save(horse: h)
    }

    func delete(_ horse: Horse) async throws {
        try await requireBackend().delete(horseID: horse.id)
    }

    /// Fills an empty stable with the 33 horses from the Equibase Virtual Stable list.
    func addStableList() async throws {
        let now = Dates.stamp()
        let have = Set(horses.map(\.id))
        let list = StableSeed.horses.filter { !have.contains($0.id) }.map { StableSeed.horse($0, now: now) }
        guard !list.isEmpty else { return }
        try await requireBackend().save(horses: list)
    }

    @ObservationIgnored private var linksChecked = false

    /// Gives horses from the stable list their Equibase page when the app knows it and the horse has none
    /// (links added to the app after the stable was filled). Once per launch.
    private func addMissingEquibaseLinks() async {
        guard !linksChecked, let backend else { return }
        linksChecked = true
        let known = Dictionary(uniqueKeysWithValues: StableSeed.horses.compactMap { s in s.equibase.map { (s.id, $0) } })
        for var h in horses where (h.equibaseUrl ?? "").isEmpty {
            guard let link = known[h.id] else { continue }
            h.equibaseUrl = link
            try? await backend.save(horse: h)
        }
    }

    // MARK: Race lines

    func save(_ line: RaceLine, for horse: Horse) async throws {
        var l = line
        l.updatedAt = Dates.stamp()
        try await requireBackend().save(line: l, horseID: horse.id)
        try await refreshSummary(horse.id)
    }

    func delete(_ line: RaceLine, for horse: Horse) async throws {
        try await requireBackend().delete(lineID: line.id, horseID: horse.id)
        try await refreshSummary(horse.id)
    }

    /// Keeps the horse's card (record and last race) current after its lines change,
    /// and fills empty profile fields from a chart.
    private func refreshSummary(_ horseID: String, profile: ChartReply.Profile? = nil, profileDate: String? = nil) async throws {
        let backend = try requireBackend()
        guard var h = horse(horseID) else { return }
        let all = try await backend.lines(horseID: horseID)
        if let p = profile {
            let newest = (h.lastRace?.date ?? "") <= (profileDate ?? "")
            func fill(_ field: WritableKeyPath<Horse, String?>, _ value: String?, always: Bool = false) {
                guard let value, !value.isEmpty else { return }
                if always || (h[keyPath: field] ?? "").isEmpty { h[keyPath: field] = value }
            }
            fill(\.trainer, p.trainer, always: newest)
            fill(\.owner, p.owner, always: newest)
            fill(\.sire, p.sire)
            fill(\.dam, p.dam)
            fill(\.damSire, p.damSire)
            fill(\.color, p.color)
            fill(\.breeder, p.breeder)
            fill(\.stateBred, p.stateBred)
        }
        h.record = Records.of(all)
        h.lastRace = Records.lastRace(all)
        h.updatedAt = Dates.stamp()
        try await backend.save(horse: h)
    }

    // MARK: Charts

    /// Your horses whose names are in a chart's text ("Told (IRE)" matches "Told" or "TOLD (IRE)").
    func horsesNamed(in text: String) -> [Horse] {
        let page = " " + Self.words(text) + " "
        return horses.filter { horse in
            let key = Self.words(Self.baseName(horse.name))
            return !key.isEmpty && page.contains(" \(key) ")
        }
    }

    static func baseName(_ name: String) -> String {
        guard let paren = name.firstIndex(of: "(") else { return name }
        return String(name[..<paren])
    }

    /// Upper-case letters and digits, single spaces.
    static func words(_ text: String) -> String {
        text.uppercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : " " }
            .joined()
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Claude reads one chart (a PDF, or text pasted from Equibase) and each listed horse's line is saved.
    func readChart(pdf: Data?, text: String?, horses list: [Horse]) async throws -> ChartOutcome {
        let backend = try requireBackend()
        let reply = try await backend.readChart(pdf: pdf, text: text, horses: list)
        var outcome = ChartOutcome()
        for found in reply.lines {
            guard let h = horse(found.horseId) ?? list.first(where: { $0.id == found.horseId }) else { continue }
            var line = found.line
            line.updatedAt = Dates.stamp()
            try await backend.save(line: line, horseID: h.id)
            try await refreshSummary(h.id, profile: found.profile, profileDate: line.date)
            let place = line.finish?.pos.map { DRF.ordinal($0) } ?? "?"
            outcome.added.append("\(h.name): \(Dates.pp(line.date)) \(DRF.trk(line.track)) · \(place) · \(DRF.money(line.earnings ?? 0))")
        }
        for missing in reply.notFound {
            let name = horse(missing.horseId)?.name ?? missing.horseId
            outcome.skipped.append(missing.reason ?? "\(name) isn’t in this chart.")
        }
        return outcome
    }

    /// The text of a PDF, for finding which of your horses are in it.
    static func text(ofPDF data: Data) -> String {
        PDFDocument(data: data)?.string ?? ""
    }

    /// A PDF shared into the app (Safari's Share button → Stable PPs, or Open in from Files).
    func receive(_ url: URL) {
        guard url.isFileURL else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            errorMessage = "Couldn’t open that file."
            return
        }
        // Files shared in are copied to the app's Inbox; they're read now, so the copy can go.
        if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        let file = ChartFile(name: url.lastPathComponent, data: data)
        if var batch = incoming {
            batch.files.append(file)
            incoming = batch
        } else {
            incoming = ChartBatch(files: [file], horseID: nil)
        }
    }

    // MARK: Condition books

    struct BookProgress {
        var done = 0
        var total = 0
        var races = 0
        var failed = 0
    }

    /// Claude reads a condition book five pages at a time (three parts at once); the races are saved
    /// as one book. Calls `progress` after each part.
    func readBook(pdf: Data, fileName: String, track: Track, title: String, year: Int,
                  progress: @escaping (BookProgress) -> Void) async throws -> ConditionBook {
        let backend = try requireBackend()
        guard let doc = PDFDocument(data: pdf), doc.pageCount > 0 else {
            throw BackendError(message: "Couldn’t open that PDF.")
        }
        var parts: [(first: Int, last: Int, data: Data)] = []
        var start = 0
        while start < doc.pageCount {
            let end = min(start + 5, doc.pageCount)
            let part = PDFDocument()
            for i in start..<end {
                if let page = doc.page(at: i)?.copy() as? PDFPage { part.insert(page, at: part.pageCount) }
            }
            if let data = part.dataRepresentation() { parts.append((start + 1, end, data)) }
            start = end
        }
        if parts.isEmpty { throw BackendError(message: "Couldn’t read the pages of that PDF.") }

        var state = BookProgress(total: parts.count)
        progress(state)
        var races: [BookRace] = []
        var firstError: Error?
        for batchStart in stride(from: 0, to: parts.count, by: 3) {
            let batch = Array(parts[batchStart..<min(batchStart + 3, parts.count)])
            let results: [Result<[BookRace], Error>] = await withTaskGroup(of: Result<[BookRace], Error>.self) { group in
                for part in batch {
                    let name = track.name
                    group.addTask {
                        do {
                            return .success(try await backend.readBookPart(pdf: part.data, trackName: name, year: year,
                                                                           first: part.first, last: part.last))
                        } catch {
                            return .failure(error)
                        }
                    }
                }
                var all: [Result<[BookRace], Error>] = []
                for await result in group { all.append(result) }
                return all
            }
            for result in results {
                switch result {
                case .success(let found): races += found
                case .failure(let error):
                    state.failed += 1
                    if firstError == nil { firstError = error }
                }
                state.done += 1
            }
            state.races = races.count
            progress(state)
            // Stop early when nothing can work (not allowed, not deployed, no key).
            if races.isEmpty, state.failed == state.done, let firstError { throw firstError }
        }

        let clean = Self.dedupe(races)
        if clean.isEmpty {
            throw firstError ?? BackendError(message: "No races were found in that PDF. Is it the condition book?")
        }
        let slug = title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let book = ConditionBook(
            id: String("\(track.code)-\(slug)".prefix(120)), track: track.code, trackName: track.name, title: title,
            year: year, from: clean.first?.date, to: clean.last?.date, races: Array(clean.prefix(600)),
            loadedAt: Dates.stamp(), file: fileName)
        try await backend.save(book: book)
        return book
    }

    /// One copy of each race (a race split across two parts can come back twice), in date order.
    static func dedupe(_ races: [BookRace]) -> [BookRace] {
        var seen = Set<String>()
        var out: [BookRace] = []
        for r in races {
            let key = "\(r.date)|\(r.raceNo ?? "")|\(r.type)|\(r.distanceF ?? 0)|\(r.claim ?? 0)|\(r.sex ?? "")|\(r.ages ?? "")"
            if seen.insert(key).inserted { out.append(r) }
        }
        return out.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            return (Int(a.raceNo ?? "") ?? 0) < (Int(b.raceNo ?? "") ?? 0)
        }
    }

    func delete(_ book: ConditionBook) async throws {
        try await requireBackend().delete(bookID: book.id)
    }
}
