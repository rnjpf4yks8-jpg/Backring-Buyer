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
    /// The administrator's People screen (requests and accounts) is open.
    var showPeople = false
    /// This phone's push notification token, once Apple hands it over.
    var deviceToken: String?

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
        await afterSignIn()
        if AppDelegate.openedFromNotification {
            AppDelegate.openedFromNotification = false
            if isAdmin { showPeople = true }
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
        await afterSignIn()
    }

    /// Everyone starts as a buyer. Picking vet, bloodstock agent or staff sends a request the
    /// administrator approves; until then the person uses the app as a buyer.
    func createAccount(name: String, email: String, password: String, role: Role) async {
        await attempt {
            user = try await backend.createAccount(name: name, email: email, password: password, role: role)
            try await reloadPurchases()
        }
        await afterSignIn()
    }

    /// Picks up a role change (an approval) made since the app opened.
    func refreshUser() async {
        guard !isDemo, user != nil else { return }
        await attempt { user = try await backend.currentUser() }
        if isAdmin { await loadPeople() }
    }

    /// The owner, once: makes this account the administrator if the code is right. Returns whether it worked.
    func claimAdmin(code: String) async -> Bool {
        var granted = false
        await attempt {
            try await backend.claimAdmin(code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            user?.role = .admin
            user?.requestedRole = nil
            granted = true
        }
        if granted { await afterSignIn() }
        return granted
    }

    /// Ask for a vet, bloodstock agent or staff role, or cancel the request (nil).
    func requestRole(_ role: Role?) async {
        guard let uid = user?.uid else { return }
        await attempt {
            try await backend.requestRole(role, uid: uid)
            user?.requestedRole = role
            user?.requestedAt = role == nil ? nil : Date()
        }
        if role != nil { await enableNotifications() }
    }

    /// Demo mode only: switch between the sample people without a password.
    func signInDemo(as person: AppUser?) async {
        await attempt {
            user = person
            try await reloadPurchases()
        }
        if isAdmin { await loadPeople() }
    }

    func signOut() async {
        if let token = deviceToken, let uid = user?.uid {
            try? await backend.removeDevice(token: token, uid: uid)
        }
        await attempt {
            try backend.signOut()
            user = nil
            people = []
            try await reloadPurchases()
        }
    }

    private func afterSignIn() async {
        guard user != nil else { return }
        if isAdmin { await loadPeople() }
        if isAdmin || user?.requestedRole != nil { await enableNotifications() }
        await saveDeviceToken()
    }

    // MARK: Administrator: requests and accounts

    /// People waiting for a role, oldest first.
    var roleRequests: [AppUser] {
        people.filter { $0.requestedRole != nil }
            .sorted { ($0.requestedAt ?? .distantPast) < ($1.requestedAt ?? .distantPast) }
    }

    func approve(_ person: AppUser) async { await decide(person, approve: true) }
    func decline(_ person: AppUser) async { await decide(person, approve: false) }

    private func decide(_ person: AppUser, approve: Bool) async {
        guard isAdmin, let role = person.requestedRole else { return }
        await attempt {
            try await backend.decide(uid: person.uid, role: role, approve: approve)
            if let i = people.firstIndex(where: { $0.uid == person.uid }) {
                if approve { people[i].role = role }
                people[i].requestedRole = nil
                people[i].requestedAt = nil
            }
        }
    }

    /// Administrator: sets anyone's role directly, including staff and administrator.
    func changeRole(of person: AppUser, to role: Role) async {
        guard isAdmin, person.uid != user?.uid, role != person.role else { return }
        await attempt {
            try await backend.setRole(role, uid: person.uid)
            if let i = people.firstIndex(where: { $0.uid == person.uid }) { people[i].role = role }
        }
    }

    /// Administrator: makes an account for someone else with their role. With no password they're emailed
    /// a link to choose one. Returns the new person, or nil if it failed (errorMessage says why).
    func addPerson(name: String, email: String, role: Role, password: String) async -> AppUser? {
        guard isAdmin else { return nil }
        var added: AppUser?
        await attempt {
            let person = try await backend.addPerson(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                role: role, password: password.isEmpty ? nil : password)
            people.append(person)
            people.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            added = person
        }
        return added
    }

    /// Emails a link to choose a new password (Forgot password, or the administrator resending it).
    func sendPasswordReset(email: String) async -> Bool {
        var sent = false
        await attempt {
            try await backend.sendPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            sent = true
        }
        return sent
    }

    /// Administrator: deletes the account for good. Returns whether it worked.
    func deleteAccount(_ person: AppUser) async -> Bool {
        guard isAdmin, person.uid != user?.uid else { return false }
        var deleted = false
        await attempt {
            try await backend.deleteAccount(uid: person.uid)
            people.removeAll { $0.uid == person.uid }
            sale.panel = sale.panel.filter { $0.value.uid != person.uid }
            deleted = true
        }
        return deleted
    }

    // MARK: Attachments

    /// Downloaded attachments, so opening one twice doesn't download it twice.
    @ObservationIgnored private var attachmentFiles: [String: URL] = [:]

    func uploadAttachment(_ data: Data, name: String, contentType: String,
                          to folder: AttachmentFolder) async throws -> Attachment {
        guard let uid = user?.uid else { throw BackendError(message: "Sign in first.") }
        return try await backend.uploadAttachment(data, name: name, contentType: contentType, to: folder, author: uid)
    }

    /// A local copy of the attachment for previewing, named the way people see it.
    func localFile(for attachment: Attachment) async throws -> URL {
        if let url = attachmentFiles[attachment.path], FileManager.default.fileExists(atPath: url.path) { return url }
        let data = try await backend.attachmentData(attachment)
        var name = attachment.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let ext = attachment.isPDF ? "pdf" : "jpg"
        if !name.lowercased().hasSuffix(".\(ext)") { name += ".\(ext)" }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .completeFileProtection)
        attachmentFiles[attachment.path] = url
        return url
    }

    /// Removes files from storage (attachments taken off before saving, or uploads that were cancelled).
    func deleteAttachments(_ attachments: [Attachment]) async {
        for attachment in attachments {
            try? await backend.deleteAttachment(attachment)
            attachmentFiles[attachment.path] = nil
        }
    }

    // MARK: Push notifications

    /// Asks once for permission to send notifications (iOS remembers the answer), then registers with Apple.
    func enableNotifications() async {
        guard !isDemo else { return }
        await PushNotifications.enable()
    }

    /// Apple handed the phone's token to the app (see Push.swift).
    func didReceive(deviceToken token: String) async {
        deviceToken = token
        await saveDeviceToken()
    }

    private func saveDeviceToken() async {
        guard !isDemo, let token = deviceToken, let uid = user?.uid else { return }
        try? await backend.saveDevice(token: token, uid: uid)
    }

    /// A notification was tapped: the administrator goes to the requests; anyone else gets their new role.
    func openedNotification() async {
        // While the app is still starting up, start() picks this up instead.
        guard !isLoading else { return }
        AppDelegate.openedFromNotification = false
        await refreshUser()
        if isAdmin { showPeople = true }
    }

    // MARK: Permissions

    /// Staff rights. The administrator has them too.
    var isStaff: Bool { user?.role == .staff || user?.role == .admin }
    var isAdmin: Bool { user?.role == .admin }

    func isAuthor(_ slot: OpinionSlot) -> Bool {
        guard let user else { return false }
        return sale.member(slot)?.uid == user.uid
    }

    func canRead(_ slot: OpinionSlot, hip: Hip) -> Bool {
        isStaff || isAuthor(slot) || purchases.contains(purchaseID(slot, hip: hip))
    }

    /// Staff edit everything, including any slot's opinion (posting it for the vet or agent, say from
    /// their PDF report); each vet and agent edits only their own slot.
    func canEdit(_ field: HipField) -> Bool {
        if field.isOpinionGroup { return isStaff || ownSlot(in: field) != nil }
        return isStaff
    }

    /// The opinion the Post or Edit button works on: for staff the one picked on screen, for a vet or
    /// agent their own.
    func editableSlot(_ field: HipField, hip: Hip) -> OpinionSlot? {
        guard field.isOpinionGroup else { return nil }
        return isStaff ? selectedSlot(field, hip: hip) : ownSlot(in: field)
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

    /// Posts or edits an opinion. A vet's or agent's own goes to staff for approval; staff can approve
    /// it as they post it (`approve`).
    func save(_ opinion: Opinion, slot: OpinionSlot, hip: Hip, approve: Bool = false) async {
        let approved = approve && isStaff
        await attempt {
            try await backend.save(opinion: opinion, saleID: sale.id, hip: hip.number, slot: slot, approved: approved)
            var saved = opinion
            saved.status = approved ? .approved : .pending
            opinions["\(hip.number)_\(slot.rawValue)"] = saved
            if let i = hips.firstIndex(where: { $0.number == hip.number }) {
                if approved { hips[i].markReviewed(slot, approved: true) } else { hips[i].markPending(slot) }
            }
        }
    }

    /// Staff: deletes an opinion and its attached files. Returns whether it worked.
    func deleteOpinion(_ slot: OpinionSlot, hip: Hip) async -> Bool {
        guard isStaff else { return false }
        let key = "\(hip.number)_\(slot.rawValue)"
        var files: [Attachment] = []
        var deleted = false
        await attempt {
            var existing = opinions[key]
            if existing == nil { existing = try await backend.loadOpinion(saleID: sale.id, hip: hip.number, slot: slot) }
            files = existing?.attachments ?? []
            try await backend.deleteOpinion(saleID: sale.id, hip: hip.number, slot: slot)
            opinions[key] = nil
            if let i = hips.firstIndex(where: { $0.number == hip.number }) { hips[i].markRemoved(slot) }
            deleted = true
        }
        if deleted { await deleteAttachments(files) }
        return deleted
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
    /// plus their own (posted or not) for a vet or agent, plus every slot for staff (posted, waiting,
    /// returned or empty), so they can post, approve or delete any of them.
    func availableSlots(_ field: HipField, hip: Hip) -> [OpinionSlot] {
        if isStaff { return field.slots }
        return field.slots.filter { hip.opinionsIn.contains($0) || isAuthor($0) }
    }

    /// The opinion shown on a Vet Opinions or Bloodstock Opinions screen: the one picked in its menu,
    /// else the user's own, else the first posted one, else the first one available.
    func selectedSlot(_ field: HipField, hip: Hip) -> OpinionSlot? {
        let available = availableSlots(field, hip: hip)
        if let picked = selectedSlots[field], available.contains(picked) { return picked }
        if let own = ownSlot(in: field), available.contains(own) { return own }
        return available.first { hip.opinionsIn.contains($0) || hip.pendingSlots.contains($0) } ?? available.first
    }

    /// Where one opinion stands for this user, e.g. "Clean", "#4 of 186", "Unlock $25", "Not posted yet".
    func slotStatus(_ slot: OpinionSlot, hip: Hip) -> (summary: String, locked: Bool) {
        if hip.pendingSlots.contains(slot), isStaff || isAuthor(slot) {
            return (isStaff ? "Needs approval" : "Waiting for approval", false)
        }
        guard hip.opinionsIn.contains(slot) else {
            if isAuthor(slot) || isStaff, opinion(slot, hip: hip)?.reviewStatus == .rejected { return ("Returned by Backring Buyer", false) }
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

    // MARK: Sales (staff)

    /// Adds a sale or saves changes to one, and features it (marked NOW) if asked. Returns whether it saved.
    func save(_ edited: Sale, feature: Bool) async -> Bool {
        var saved = false
        await attempt {
            try await backend.save(sale: edited)
            if feature { try await backend.setFeaturedSale(edited.id) }
            if let i = sales.firstIndex(where: { $0.id == edited.id }) {
                sales[i].name = edited.name
                sales[i].company = edited.company
                sales[i].date = edited.date
                if let code = edited.fasigSale { sales[i].fasigSale = code }
            } else {
                sales.append(edited)
                hipCounts[edited.id] = 0
            }
            if sale.id == edited.id {
                sale.name = edited.name
                sale.company = edited.company
                sale.date = edited.date
                if let code = edited.fasigSale { sale.fasigSale = code }
            }
            sales.sort { ($0.day ?? .distantPast, $0.name) > ($1.day ?? .distantPast, $1.name) }
            if feature { featuredSaleID = edited.id }
            saved = true
        }
        return saved
    }

    /// Administrator: deletes a sale with all its hips, vet reports, opinions and files. Returns whether it worked.
    func deleteSale(_ target: Sale) async -> Bool {
        guard isAdmin else { return false }
        var deleted = false
        await attempt {
            try await backend.deleteSale(target.id)
            sales.removeAll { $0.id == target.id }
            hipCounts[target.id] = nil
            if featuredSaleID == target.id { featuredSaleID = nil }
            if sale.id == target.id {
                hips = []
                opinions = [:]
                currentHipNumber = 0
            }
            deleted = true
        }
        return deleted
    }

    /// What deleting a sale takes with it, for the confirmation.
    func deleteSaleWarning(_ target: Sale) -> String {
        let count = hipCounts[target.id].map { $0 == 1 ? "its 1 hip" : "its \($0.formatted()) hips" } ?? "all its hips"
        return "\(target.name) and \(count) are deleted for good, with every vet report, vet and bloodstock opinion and attached PDF. Buyers can no longer open opinions they bought in this sale."
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

    // MARK: Fasig-Tipton (administrator)

    struct FasigResult {
        var saleID: String
        var saleName: String
        var added: Int
        var updated: Int
    }

    /// The app sale a Fasig-Tipton catalog goes into: one already linked to that sale code, or a
    /// Fasig-Tipton sale on the same date (made by hand earlier). Nil means a new sale is made.
    func appSale(for catalog: FasigTipton.Catalog) -> Sale? {
        if let linked = sales.first(where: { $0.fasigSale?.caseInsensitiveCompare(catalog.code) == .orderedSame }) {
            return linked
        }
        guard let day = catalog.day else { return nil }
        return sales.first { $0.date == Sale.dateText(day) && $0.company.lowercased().contains("fasig") }
    }

    /// Administrator: puts a Fasig-Tipton catalog into the app: makes (or reuses) the sale, adds new hips,
    /// and updates hips already there. Staff uploads stay: an uploaded walk video, sale picture or catalog
    /// page is only replaced by Fasig-Tipton's when it came from Fasig-Tipton in the first place.
    func importFasigTipton(_ catalog: FasigTipton.Catalog, into chosen: Sale?, feature: Bool) async -> FasigResult? {
        guard isAdmin else { return nil }
        let day = catalog.day ?? Date()
        var target = chosen ?? appSale(for: catalog) ?? Sale(
            id: Sale.makeID(company: "Fasig-Tipton", day: day, taken: Set(sales.map(\.id))),
            name: catalog.name, company: "Fasig-Tipton", date: Sale.dateText(day))
        target.fasigSale = catalog.code
        guard await save(target, feature: feature) else { return nil }

        var result: FasigResult?
        await attempt {
            let existing = Dictionary(try await backend.loadHips(saleID: target.id).map { ($0.number, $0) },
                                      uniquingKeysWith: { first, _ in first })
            func fromFasig(_ url: URL?) -> Bool {
                guard let host = url?.host()?.lowercased() else { return true }  // nothing there yet
                return ["fasigtipton", "vimeo", "youtube", "youtu.be"].contains { host.contains($0) }
            }
            let rows = catalog.horses.map { horse -> CatalogImport.Row in
                var row = FasigTipton.row(horse, saleDay: catalog.day)
                if let hip = existing[horse.hip] {
                    if !fromFasig(hip.walkVideoURL) { row.walkVideoURL = nil }
                    if !fromFasig(hip.photoURL) { row.photoURL = nil }
                    if !fromFasig(hip.pedigreeURL) { row.pedigreeURL = nil }
                }
                return row
            }
            let counts = try await backend.importCatalog(rows, saleID: target.id)
            hipCounts[target.id] = existing.count + counts.added
            result = FasigResult(saleID: target.id, saleName: target.name, added: counts.added, updated: counts.updated)
        }
        if result != nil, sale.id == target.id { await open(saleID: target.id) }
        return result
    }

    /// Staff: imports a catalog spreadsheet into the open sale, then reloads its hips.
    func importCatalog(_ catalog: CatalogImport) async -> (added: Int, updated: Int)? {
        var result: (added: Int, updated: Int)?
        let saleID = sale.id
        await attempt {
            result = try await backend.importCatalog(catalog.rows, saleID: saleID)
        }
        if result != nil { await open(saleID: saleID) }
        return result
    }

    func upload(_ data: Data, kind: MediaKind, hip: Hip) async -> URL? {
        var url: URL?
        await attempt {
            url = try await backend.upload(data, kind: kind, saleID: sale.id, hip: hip.number)
        }
        return url
    }

    /// Staff only: the AI's conformation grade from this hip's saved sale walk video. Throws with a
    /// message staff can act on (no video, a Vimeo/YouTube link, AI not set up).
    func suggestConformation(for hip: Hip) async throws -> ConformationSuggestion {
        try await backend.suggestConformation(saleID: sale.id, hip: hip.number)
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

    /// How many hips in the open sale have a conformation grade.
    var conformationGradedCount: Int { hips.filter { $0.conformationGrade != nil }.count }

    /// How many hips in the open sale have a pedigree grade.
    var pedigreeGradedCount: Int { hips.filter { $0.pedigreeGrade != nil }.count }

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
        case .vetReport: summary = vetReportSummary(hip.vetReport)
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

    /// The worst grade staff gave, or what's attached when they only uploaded the report.
    private func vetReportSummary(_ report: VetReport) -> String {
        guard report.isEntered else { return "Not entered" }
        if report.hasSummary { return worst(report.radiographs, report.scope).label }
        let files = report.attachments ?? []
        if files.isEmpty { return report.filed.isEmpty ? "Entered" : "Filed \(report.filed)" }
        if files.count == 1 { return files[0].isPDF ? "1 PDF" : "1 file" }
        return files.allSatisfy(\.isPDF) ? "\(files.count) PDFs" : "\(files.count) files"
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
