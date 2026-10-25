import Foundation
import Observation

/// App state. Reads and writes go through a SaleBackend: Firebase when the app has a
/// GoogleService-Info.plist, otherwise the in-memory sample data.
@MainActor
@Observable
final class SaleStore {
    let backend: SaleBackend
    /// Every sale, newest first.
    var sales: [Sale] = []
    var featuredSaleID: String?
    /// Hips per sale, for the sales list. Filled in as counts arrive.
    var hipCounts: [String: Int] = [:]
    /// The sale that's open. Hips and opinions belong to it.
    var sale = SampleData.sale
    var hips: [Hip] = []
    var currentHipNumber = 0
    var user: AppUser?
    /// Purchase ids this user owns, "<saleID>_<hip>_<slot>".
    var purchases: Set<String> = []
    /// Opinions loaded so far, keyed "<hip>_<slot>".
    var opinions: [String: Opinion] = [:]
    var isLoading = true
    var errorMessage: String?

    init(backend: SaleBackend) {
        self.backend = backend
    }

    var isDemo: Bool { backend.isDemo }

    var currentHip: Hip? { hip(currentHipNumber) ?? hips.first }

    func hip(_ number: Int) -> Hip? {
        hips.first { $0.number == number }
    }

    // MARK: Loading

    func start() async {
        isLoading = true
        defer { isLoading = false }
        await attempt {
            user = try await backend.currentUser()
            try await reloadSales()
            try await reloadPurchases()
        }
        await loadHipCounts()
    }

    func reloadSales() async throws {
        featuredSaleID = try await backend.featuredSaleID()
        sales = try await backend.loadSales().sorted {
            ($0.day ?? .distantPast, $0.name) > ($1.day ?? .distantPast, $1.name)
        }
    }

    /// Purchases cover every sale, so they reload with the account, not with the sale.
    private func reloadPurchases() async throws {
        purchases = []
        if let user { purchases = try await backend.loadPurchases(uid: user.uid) }
        opinions = [:]
    }

    private func loadHipCounts() async {
        for sale in sales where hipCounts[sale.id] == nil {
            if let count = try? await backend.hipCount(saleID: sale.id) { hipCounts[sale.id] = count }
        }
    }

    /// Opens a sale from the sales list. Its hips load fresh each time it's opened.
    func open(saleID: String) async {
        guard let picked = sales.first(where: { $0.id == saleID }) else { return }
        if picked.id != sale.id {
            sale = picked
            hips = []
            currentHipNumber = 0
            opinions = [:]
        }
        isLoading = true
        defer { isLoading = false }
        await attempt {
            let loaded = try await backend.loadHips(saleID: picked.id).sorted { $0.number < $1.number }
            guard sale.id == picked.id else { return }  // Another sale was opened meanwhile.
            hips = loaded
            hipCounts[picked.id] = loaded.count
            if hip(currentHipNumber) == nil { currentHipNumber = hips.first?.number ?? 0 }
        }
    }

    /// Reloads the sales list (pull to refresh).
    func refreshSales() async {
        await attempt { try await reloadSales() }
        hipCounts = [:]
        await loadHipCounts()
    }

    // MARK: Account

    func signIn(email: String, password: String) async {
        await attempt {
            user = try await backend.signIn(email: email, password: password)
            try await reloadPurchases()
        }
    }

    func createAccount(name: String, email: String, password: String) async {
        await attempt {
            user = try await backend.createAccount(name: name, email: email, password: password)
            try await reloadPurchases()
        }
    }

    /// Demo mode only: switch between the sample people without a password.
    func signInDemo(as person: AppUser?) async {
        await attempt {
            user = person
            try await reloadPurchases()
        }
    }

    func signOut() async {
        await attempt {
            try backend.signOut()
            user = nil
            try await reloadPurchases()
        }
    }

    // MARK: Permissions

    var isStaff: Bool { user?.role == .staff }

    func isAuthor(_ slot: OpinionSlot) -> Bool {
        guard let user else { return false }
        return sale.member(slot)?.uid == user.uid
    }

    func canRead(_ slot: OpinionSlot, hip: Hip) -> Bool {
        isStaff || isAuthor(slot) || purchases.contains(purchaseID(slot, hip: hip))
    }

    /// Staff edit everything except opinions; each vet and agent edits only their own slot.
    func canEdit(_ field: HipField) -> Bool {
        if let slot = field.slot { return isAuthor(slot) }
        return isStaff
    }

    // MARK: Opinions

    func opinion(_ slot: OpinionSlot, hip: Hip) -> Opinion? {
        opinions["\(hip.number)_\(slot.rawValue)"]
    }

    func loadOpinion(_ slot: OpinionSlot, hip: Hip) async {
        guard canRead(slot, hip: hip), opinion(slot, hip: hip) == nil else { return }
        await attempt {
            if let found = try await backend.loadOpinion(saleID: sale.id, hip: hip.number, slot: slot) {
                opinions["\(hip.number)_\(slot.rawValue)"] = found
            }
        }
    }

    func save(_ opinion: Opinion, slot: OpinionSlot, hip: Hip) async {
        await attempt {
            try await backend.save(opinion: opinion, saleID: sale.id, hip: hip.number, slot: slot)
            opinions["\(hip.number)_\(slot.rawValue)"] = opinion
            if let i = hips.firstIndex(where: { $0.number == hip.number }), !hips[i].opinionsIn.contains(slot) {
                hips[i].opinionsIn.append(slot)
            }
        }
    }

    func buy(_ slot: OpinionSlot, hip: Hip) async {
        guard let user else { return }
        await attempt {
            try await backend.recordPurchase(uid: user.uid, saleID: sale.id, hip: hip.number, slot: slot)
            purchases.insert(purchaseID(slot, hip: hip))
            await loadOpinion(slot, hip: hip)
        }
    }

    func purchaseID(_ slot: OpinionSlot, hip: Hip) -> String {
        "\(sale.id)_\(hip.number)_\(slot.rawValue)"
    }

    // MARK: Hips (staff)

    /// Saves a hip. If staff changed its number, the old entry is replaced.
    func save(_ hip: Hip, replacing oldNumber: Int? = nil) async {
        await attempt {
            try await backend.save(hip: hip, saleID: sale.id)
            if let oldNumber, oldNumber != hip.number {
                try await backend.deleteHip(number: oldNumber, saleID: sale.id)
                hips.removeAll { $0.number == oldNumber }
            }
            if let i = hips.firstIndex(where: { $0.number == hip.number }) {
                hips[i] = hip
            } else {
                hips.append(hip)
                hips.sort { $0.number < $1.number }
                hipCounts[sale.id] = hips.count
            }
            currentHipNumber = hip.number
        }
    }

    func upload(_ data: Data, kind: MediaKind, hip: Hip) async -> URL? {
        var url: URL?
        await attempt {
            url = try await backend.upload(data, kind: kind, saleID: sale.id, hip: hip.number)
        }
        return url
    }

    // MARK: Navigation

    var currentIndex: Int { hips.firstIndex { $0.number == currentHipNumber } ?? 0 }
    var hasPreviousHip: Bool { currentIndex > 0 }
    var hasNextHip: Bool { currentIndex < hips.count - 1 }

    /// Moves to the previous (-1) or next (+1) hip in catalog order.
    func stepHip(_ delta: Int) {
        let target = currentIndex + delta
        guard hips.indices.contains(target) else { return }
        currentHipNumber = hips[target].number
    }

    private func attempt(_ work: () async throws -> Void) async {
        do {
            errorMessage = nil
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Home screen tiles

extension SaleStore {
    /// One-line value for a home-screen button, and whether it is a paid opinion this user hasn't bought.
    func tileState(_ field: HipField, hip: Hip) -> (summary: String, locked: Bool) {
        if let slot = field.slot {
            guard hip.opinionsIn.contains(slot) else { return ("Not posted yet", false) }
            guard canRead(slot, hip: hip) else { return ("Unlock · \(usd(sale.price(slot)))", true) }
            guard let opinion = opinion(slot, hip: hip) else { return ("Unlocked", false) }
            if slot.isVet { return (opinion.grade?.label ?? "Posted", false) }
            if let rank = opinion.rank, let outOf = opinion.outOf { return ("#\(rank) of \(outOf)", false) }
            return ("Posted", false)
        }
        let summary: String
        switch field {
        case .hipNumber: summary = "#\(hip.number)"
        case .vetReport: summary = !hip.vetReport.isEntered ? "Not entered" : worst(hip.vetReport.radiographs, hip.vetReport.scope).label
        case .pedigree: summary = hip.pedigree.sire.isEmpty ? "Not entered" : "by \(hip.pedigree.sire)"
        case .auctionHistory: summary = hip.auctionHistory.isEmpty ? "First sale" : "\(hip.auctionHistory.count) prior"
        case .reserve: summary = hip.reserve.map(usd) ?? "No reserve"
        case .saleWalkVideo: summary = hip.walkVideoURL == nil ? "Not posted" : (hip.walkVideoLength.isEmpty ? "Posted" : hip.walkVideoLength)
        case .salePicture: summary = hip.photoURL == nil ? "Not posted" : "1 photo"
        case .hp: summary = hip.physical.map { "\($0.heightHands) · \(Int($0.lengthInches))″" } ?? "Not measured"
        default: summary = ""
        }
        return (summary, false)
    }

    private func worst(_ a: Grade, _ b: Grade) -> Grade {
        let order = Grade.allCases
        return order.firstIndex(of: a)! >= order.firstIndex(of: b)! ? a : b
    }
}
