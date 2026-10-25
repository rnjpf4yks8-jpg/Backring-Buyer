import Foundation
import Observation

/// App state. Reads and writes go through a SaleBackend: Firebase when the app has a
/// GoogleService-Info.plist, otherwise the in-memory sample data.
@MainActor
@Observable
final class SaleStore {
    let backend: SaleBackend
    let payments = Payments()
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
    /// The opinion picked in the menu on the Vet Opinions and Bloodstock Opinions screens.
    var selectedSlots: [HipField: OpinionSlot] = [:]
    /// Everyone with an account. Loaded when staff open the Panel screen.
    var people: [AppUser] = []
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
        if !isDemo { await payments.loadProducts() }
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
        if field.isOpinionGroup { return ownSlot(in: field) != nil }
        return isStaff
    }

    /// The signed-in vet's or agent's own slot under Vet Opinions or Bloodstock Opinions, if they have one.
    func ownSlot(in field: HipField) -> OpinionSlot? {
        field.slots.first { isAuthor($0) }
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
            var pending = opinion
            pending.status = .pending
            opinions["\(hip.number)_\(slot.rawValue)"] = pending
            if let i = hips.firstIndex(where: { $0.number == hip.number }) { hips[i].markPending(slot) }
        }
    }

    /// Staff only: approve an opinion so buyers can see it, or return it to its author.
    func review(_ slot: OpinionSlot, hip: Hip, approve: Bool) async {
        await attempt {
            try await backend.review(approve: approve, saleID: sale.id, hip: hip.number, slot: slot)
            opinions["\(hip.number)_\(slot.rawValue)"]?.status = approve ? .approved : .rejected
            if let i = hips.firstIndex(where: { $0.number == hip.number }) { hips[i].markReviewed(slot, approved: approve) }
        }
    }

    /// Opinions in the open sale waiting for staff approval, in catalog order.
    var approvalQueue: [PendingOpinion] {
        hips.flatMap { hip in hip.pendingSlots.map { PendingOpinion(hip: hip, slot: $0) } }
    }

    /// Buys one opinion with Apple in-app purchase (demo mode skips payment).
    func buy(_ slot: OpinionSlot, hip: Hip) async {
        guard let user else { return }
        let id = purchaseID(slot, hip: hip)
        await attempt {
            if isDemo {
                try await backend.recordPurchase(uid: user.uid, purchaseID: id, receipt: nil)
            } else {
                switch try await payments.purchase(slot, purchaseID: "\(user.uid)/\(id)") {
                case .cancelled:
                    return
                case .pending:
                    throw BackendError(message: "Your purchase is waiting for approval. The opinion unlocks as soon as it goes through.")
                case .paid(let receipt, let transaction):
                    try await backend.recordPurchase(uid: user.uid, purchaseID: id, receipt: receipt)
                    await payments.finish(transaction)
                }
            }
            purchases.insert(id)
            await loadOpinion(slot, hip: hip)
        }
    }

    /// Records purchases that finished outside the purchase sheet (Ask to Buy, or the app closed mid-purchase).
    func settlePurchases() async {
        await payments.settle { [weak self] intent, receipt in
            guard let self else { return false }
            let parts = intent.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0] == self.user?.uid else { return false }
            do {
                try await self.backend.recordPurchase(uid: parts[0], purchaseID: parts[1], receipt: receipt)
                self.purchases.insert(parts[1])
                return true
            } catch {
                return false
            }
        }
    }

    /// The price buyers pay: the App Store's price (set in App Store Connect), or the sale's price in demo mode.
    func price(_ slot: OpinionSlot) -> String {
        payments.displayPrice(slot) ?? usd(sale.price(slot))
    }

    func purchaseID(_ slot: OpinionSlot, hip: Hip) -> String {
        "\(sale.id)_\(hip.number)_\(slot.rawValue)"
    }

    /// The opinions under a button that this user can pick in its menu: approved ones for everyone,
    /// plus their own (posted or not) for a vet or agent, plus ones waiting for approval for staff.
    func availableSlots(_ field: HipField, hip: Hip) -> [OpinionSlot] {
        field.slots.filter { slot in
            hip.opinionsIn.contains(slot) || isAuthor(slot) || (isStaff && hip.pendingSlots.contains(slot))
        }
    }

    /// The opinion shown on a Vet Opinions or Bloodstock Opinions screen: the one picked in its menu,
    /// else the user's own, else the first one available.
    func selectedSlot(_ field: HipField, hip: Hip) -> OpinionSlot? {
        let available = availableSlots(field, hip: hip)
        if let picked = selectedSlots[field], available.contains(picked) { return picked }
        if let own = ownSlot(in: field), available.contains(own) { return own }
        return available.first
    }

    /// Where one opinion stands for this user, e.g. "Clean", "#4 of 186", "Unlock $25", "Not posted yet".
    func slotStatus(_ slot: OpinionSlot, hip: Hip) -> (summary: String, locked: Bool) {
        if hip.pendingSlots.contains(slot), isStaff || isAuthor(slot) {
            return (isStaff ? "Needs approval" : "Waiting for approval", false)
        }
        guard hip.opinionsIn.contains(slot) else {
            if isAuthor(slot), opinion(slot, hip: hip)?.reviewStatus == .rejected { return ("Returned by HAINTEL", false) }
            return ("Not posted yet", false)
        }
        guard canRead(slot, hip: hip) else { return ("Unlock \(price(slot))", true) }
        guard let opinion = opinion(slot, hip: hip) else { return ("Unlocked", false) }
        if slot.isVet { return (opinion.grade?.label ?? "Posted", false) }
        if let rank = opinion.rank, let outOf = opinion.outOf { return ("#\(rank) of \(outOf)", false) }
        return ("Posted", false)
    }

    /// A menu row: the panel member's name and where their opinion stands.
    func slotMenuTitle(_ slot: OpinionSlot, hip: Hip) -> String {
        "\(sale.member(slot)?.name ?? slot.title) — \(slotStatus(slot, hip: hip).summary)"
    }

    // MARK: Panel (staff)

    func loadPeople() async {
        await attempt {
            people = try await backend.loadPeople().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    /// Saves who holds Vet 1, Vet 2, BS1 and BS2 for the open sale. A buyer who is given a slot
    /// becomes a vet or agent; staff keep their role.
    func savePanel(_ panel: [String: PanelMember]) async -> Bool {
        var saved = false
        await attempt {
            for (key, member) in panel {
                guard let slot = OpinionSlot(rawValue: key),
                      let i = people.firstIndex(where: { $0.uid == member.uid }),
                      people[i].role == .buyer else { continue }
                let role: Role = slot.isVet ? .vet : .agent
                try await backend.setRole(role, uid: member.uid)
                people[i].role = role
            }
            try await backend.savePanel(panel, saleID: sale.id)
            sale.panel = panel
            if let i = sales.firstIndex(where: { $0.id == sale.id }) { sales[i].panel = panel }
            saved = true
        }
        return saved
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

    // MARK: Grades

    /// Rank of the hip's conformation grade (C) in the open sale. Ties share a rank; ungraded hips have none.
    func conformationRank(_ hip: Hip) -> Int? {
        rank(hip.conformationGrade, among: hips.compactMap { $0.conformationGrade })
    }

    /// Rank of the hip's pedigree grade (P) in the open sale. Ties share a rank; ungraded hips have none.
    func pedigreeRank(_ hip: Hip) -> Int? {
        rank(hip.pedigreeGrade, among: hips.compactMap { $0.pedigreeGrade })
    }

    /// Rank of the hip's combined grade (C + P, out of 15) in the open sale. Nil unless it has both grades.
    func combinedRank(_ hip: Hip) -> Int? {
        rank(hip.combinedGrade, among: hips.compactMap { $0.combinedGrade })
    }

    /// How many hips in the open sale have a conformation grade.
    var conformationGradedCount: Int { hips.filter { $0.conformationGrade != nil }.count }

    /// How many hips in the open sale have a pedigree grade.
    var pedigreeGradedCount: Int { hips.filter { $0.pedigreeGrade != nil }.count }

    /// How many hips in the open sale have both grades, and so a combined grade.
    var combinedGradedCount: Int { hips.filter { $0.combinedGrade != nil }.count }

    /// 1 + the number of grades strictly higher than this one.
    private func rank(_ grade: Double?, among grades: [Double]) -> Int? {
        guard let grade else { return nil }
        return 1 + grades.filter { $0 > grade }.count
    }

    // MARK: Navigation

    var currentIndex: Int { hips.firstIndex { $0.number == currentHipNumber } ?? 0 }
    var hasPreviousHip: Bool { currentIndex > 0 }
    var hasNextHip: Bool { currentIndex < hips.count - 1 }

    /// Jumps to the hip number typed in "Go to hip".
    func goToHip(_ text: String) {
        guard let number = Int(text.trimmingCharacters(in: .whitespaces)) else { return }
        if hip(number) != nil {
            currentHipNumber = number
        } else {
            errorMessage = "Hip \(number) isn’t in \(sale.name)."
        }
    }

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
        if field.isOpinionGroup { return groupTileState(field, hip: hip) }
        let summary: String
        switch field {
        case .hipNumber: summary = "#\(hip.number)"
        case .vetReport: summary = !hip.vetReport.isEntered ? "Not entered" : worst(hip.vetReport.radiographs, hip.vetReport.scope).label
        case .pedigree:
            let grade: String? = hip.pedigreeGrade.map { "P \(Hip.gradeText($0))/5" }
            let sire: String? = hip.pedigree.sire.isEmpty ? nil : "by \(hip.pedigree.sire)"
            let parts = [grade, sire].compactMap { $0 }
            summary = parts.isEmpty ? "Not entered" : parts.joined(separator: " · ")
        case .auctionHistory: summary = hip.auctionHistory.isEmpty ? "First sale" : "\(hip.auctionHistory.count) prior"
        case .reserve: summary = hip.reserve.map(usd) ?? "No reserve"
        case .saleWalkVideo: summary = hip.walkVideoURL == nil ? "Not posted" : (hip.walkVideoLength.isEmpty ? "Posted" : hip.walkVideoLength)
        case .salePicture: summary = hip.photoURL == nil ? "Not posted" : "1 photo"
        case .hp: summary = hip.physical.map { "\($0.heightHands) · \(Int($0.lengthInches))″" } ?? "Not measured"
        case .vetOpinions, .bloodstockOpinions: summary = ""
        }
        return (summary, false)
    }

    /// Vet Opinions and Bloodstock Opinions: how many are posted and whether this user still has any to unlock.
    private func groupTileState(_ field: HipField, hip: Hip) -> (summary: String, locked: Bool) {
        let slots = field.slots
        let pending = slots.filter { hip.pendingSlots.contains($0) }
        if isStaff, !pending.isEmpty {
            return (pending.count == 1 ? "Needs approval" : "\(pending.count) need approval", false)
        }
        // A vet or agent whose own opinion isn't approved yet sees where it stands.
        if let own = ownSlot(in: field), !hip.opinionsIn.contains(own) {
            return (slotStatus(own, hip: hip).summary, false)
        }
        let posted = slots.filter { hip.opinionsIn.contains($0) }
        guard !posted.isEmpty else { return ("None posted", false) }
        let noun = field == .vetOpinions ? "vet" : "agent"
        let count = posted.count == 1 ? "1 \(noun)" : "\(posted.count) \(noun)s"
        let locked = posted.filter { !canRead($0, hip: hip) }
        if let lockedSlot = locked.first {
            return ("\(count) · unlock \(locked.count > 1 ? "from " : "")\(price(lockedSlot))", true)
        }
        return ("\(count) · \(posted.count == 1 ? "unlocked" : "all unlocked")", false)
    }

    private func worst(_ a: Grade, _ b: Grade) -> Grade {
        let order = Grade.allCases
        return order.firstIndex(of: a)! >= order.firstIndex(of: b)! ? a : b
    }
}

struct PendingOpinion {
    let hip: Hip
    let slot: OpinionSlot
    var key: String { "\(hip.number)_\(slot.rawValue)" }
}
