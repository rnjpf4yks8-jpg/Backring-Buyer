import Foundation

enum MediaKind {
    case photo, walkVideo

    var fileName: String { self == .photo ? "photo.jpg" : "walk.mov" }
    var contentType: String { self == .photo ? "image/jpeg" : "video/quicktime" }
}

/// Everything the app reads or writes. FirebaseBackend talks to Firebase;
/// SampleBackend keeps sample data in memory so the app runs before Firebase is set up.
protocol SaleBackend {
    var isDemo: Bool { get }

    func currentUser() async throws -> AppUser?
    func signIn(email: String, password: String) async throws -> AppUser
    func createAccount(name: String, email: String, password: String) async throws -> AppUser
    func signOut() throws

    func loadSales() async throws -> [Sale]
    /// The sale HAINTEL is featuring now (config/app.currentSale), if one is set.
    func featuredSaleID() async throws -> String?
    func hipCount(saleID: String) async throws -> Int
    func loadHips(saleID: String) async throws -> [Hip]
    func save(hip: Hip, saleID: String) async throws
    func deleteHip(number: Int, saleID: String) async throws
    func upload(_ data: Data, kind: MediaKind, saleID: String, hip: Int) async throws -> URL

    func loadOpinion(saleID: String, hip: Int, slot: OpinionSlot) async throws -> Opinion?
    /// The author posts or edits an opinion. It waits for HAINTEL approval before buyers see it.
    func save(opinion: Opinion, saleID: String, hip: Int, slot: OpinionSlot) async throws
    /// Staff approve (buyers can see it) or return (hidden) a posted opinion.
    func review(approve: Bool, saleID: String, hip: Int, slot: OpinionSlot) async throws

    /// Staff only: everyone with an account, for picking a sale's vets and agents.
    func loadPeople() async throws -> [AppUser]
    func setRole(_ role: Role, uid: String) async throws
    func savePanel(_ panel: [String: PanelMember], saleID: String) async throws

    func loadPurchases(uid: String) async throws -> Set<String>
    /// Saves that `uid` owns an opinion. `receipt` is the App Store's proof of payment (nil in demo mode).
    func recordPurchase(uid: String, purchaseID: String, receipt: PurchaseReceipt?) async throws
}

struct BackendError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// In-memory backend with sample data. Nothing is saved between launches.
final class SampleBackend: SaleBackend {
    let isDemo = true
    private var hipsBySale = [SampleData.sale.id: SampleData.hips]
    private var sales = SampleData.sales
    private var people = SampleData.people
    private var opinions = SampleData.opinions
    private var purchases: [String: Set<String>] = [:]

    func currentUser() async throws -> AppUser? { nil }

    func signIn(email: String, password: String) async throws -> AppUser {
        throw BackendError(message: "Demo mode has no passwords. Pick a sample person instead.")
    }

    func createAccount(name: String, email: String, password: String) async throws -> AppUser {
        throw BackendError(message: "Demo mode can't create accounts. Pick a sample person instead.")
    }

    func signOut() throws {}

    func loadSales() async throws -> [Sale] { sales }

    func featuredSaleID() async throws -> String? { SampleData.sale.id }

    func hipCount(saleID: String) async throws -> Int { hipsBySale[saleID]?.count ?? 0 }

    func loadHips(saleID: String) async throws -> [Hip] { hipsBySale[saleID] ?? [] }

    func save(hip: Hip, saleID: String) async throws {
        var hips = hipsBySale[saleID] ?? []
        if let i = hips.firstIndex(where: { $0.number == hip.number }) { hips[i] = hip } else { hips.append(hip) }
        hipsBySale[saleID] = hips
    }

    func deleteHip(number: Int, saleID: String) async throws {
        hipsBySale[saleID]?.removeAll { $0.number == number }
    }

    func upload(_ data: Data, kind: MediaKind, saleID: String, hip: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(hip)-\(kind.fileName)")
        try data.write(to: url)
        return url
    }

    func loadOpinion(saleID: String, hip: Int, slot: OpinionSlot) async throws -> Opinion? {
        opinions["\(hip)_\(slot.rawValue)"]
    }

    func save(opinion: Opinion, saleID: String, hip: Int, slot: OpinionSlot) async throws {
        opinions["\(hip)_\(slot.rawValue)"] = opinion
        guard let i = hipsBySale[saleID]?.firstIndex(where: { $0.number == hip }), var entry = hipsBySale[saleID]?[i] else { return }
        entry.markPending(slot)
        hipsBySale[saleID]?[i] = entry
    }

    func review(approve: Bool, saleID: String, hip: Int, slot: OpinionSlot) async throws {
        opinions["\(hip)_\(slot.rawValue)"]?.status = approve ? .approved : .rejected
        guard let i = hipsBySale[saleID]?.firstIndex(where: { $0.number == hip }), var entry = hipsBySale[saleID]?[i] else { return }
        entry.markReviewed(slot, approved: approve)
        hipsBySale[saleID]?[i] = entry
    }

    func loadPeople() async throws -> [AppUser] { people }

    func setRole(_ role: Role, uid: String) async throws {
        if let i = people.firstIndex(where: { $0.uid == uid }) { people[i].role = role }
    }

    func savePanel(_ panel: [String: PanelMember], saleID: String) async throws {
        if let i = sales.firstIndex(where: { $0.id == saleID }) { sales[i].panel = panel }
    }

    func loadPurchases(uid: String) async throws -> Set<String> { purchases[uid] ?? [] }

    func recordPurchase(uid: String, purchaseID: String, receipt: PurchaseReceipt?) async throws {
        purchases[uid, default: []].insert(purchaseID)
    }
}
