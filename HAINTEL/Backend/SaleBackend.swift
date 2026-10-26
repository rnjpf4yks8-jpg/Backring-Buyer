import Foundation

enum MediaKind {
    case photo, walkVideo

    var fileName: String { self == .photo ? "photo.jpg" : "walk.mov" }
    var contentType: String { self == .photo ? "image/jpeg" : "video/quicktime" }
}

/// Where an attachment is stored. Storage rules give each folder its own readers.
enum AttachmentFolder {
    /// A vet's or agent's opinion: the author, staff, and buyers who bought it.
    case opinion(saleID: String, hip: Int, slot: OpinionSlot)
    /// The hip's vet report: staff upload, signed-in users open.
    case vetReport(saleID: String, hip: Int)

    var path: String {
        switch self {
        case let .opinion(saleID, hip, slot): "sales/\(saleID)/hips/\(hip)/opinions/\(slot.rawValue)"
        case let .vetReport(saleID, hip): "sales/\(saleID)/hips/\(hip)/vetReport"
        }
    }
}

/// The AI's conformation grade from a hip's sale walk video. Staff accept or change it before it's saved.
struct ConformationSuggestion: Decodable, Hashable {
    /// 1–10 in half points, like the C grade staff enter.
    var grade: Double
    /// "low", "medium" or "high": how well the video let the AI judge the horse.
    var confidence: String
    var summary: String
    var strengths: [String]
    var faults: [String]
    /// What the video didn't show. Empty when nothing.
    var limits: String
    /// Still frames from the video the AI looked at.
    var frames: Int
}

/// Everything the app reads or writes. FirebaseBackend talks to Firebase;
/// SampleBackend keeps sample data in memory so the app runs before Firebase is set up.
protocol SaleBackend {
    var isDemo: Bool { get }

    func currentUser() async throws -> AppUser?
    func signIn(email: String, password: String) async throws -> AppUser
    /// New accounts are buyers. Any other `role` is saved as a request for the administrator to approve.
    func createAccount(name: String, email: String, password: String, role: Role) async throws -> AppUser
    /// Makes the signed-in user the administrator if `code` is right and there's no administrator yet.
    func claimAdmin(code: String) async throws
    /// Asks for a vet, agent or staff role, or cancels the request (nil).
    func requestRole(_ role: Role?, uid: String) async throws
    /// Administrator: approves (gives them the role they asked for) or declines a request.
    func decide(uid: String, role: Role, approve: Bool) async throws
    /// Administrator: deletes a person's sign-in and profile and takes them off every panel.
    func deleteAccount(uid: String) async throws
    /// The phone's push notification token for this person (removed on sign-out).
    func saveDevice(token: String, uid: String) async throws
    func removeDevice(token: String, uid: String) async throws
    func signOut() throws

    func loadSales() async throws -> [Sale]
    /// The sale Backring Buyer is featuring now (config/app.currentSale), if one is set.
    func featuredSaleID() async throws -> String?
    func hipCount(saleID: String) async throws -> Int
    func loadHips(saleID: String) async throws -> [Hip]
    func save(hip: Hip, saleID: String) async throws
    func deleteHip(number: Int, saleID: String) async throws
    func upload(_ data: Data, kind: MediaKind, saleID: String, hip: Int) async throws -> URL
    /// Uploads a PDF or JPEG report file under a new, unguessable name. `author` is the uploader's uid.
    func uploadAttachment(_ data: Data, name: String, contentType: String, to folder: AttachmentFolder,
                          author: String) async throws -> Attachment
    /// Downloads an attachment the signed-in user is allowed to open.
    func attachmentData(_ attachment: Attachment) async throws -> Data
    func deleteAttachment(_ attachment: Attachment) async throws
    /// Staff only: the AI's conformation grade from the hip's saved sale walk video. Nothing is saved.
    func suggestConformation(saleID: String, hip: Int) async throws -> ConformationSuggestion

    func loadOpinion(saleID: String, hip: Int, slot: OpinionSlot) async throws -> Opinion?
    /// The author posts or edits an opinion. It waits for Backring Buyer approval before buyers see it.
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
    private var files: [String: Data] = [:]

    func currentUser() async throws -> AppUser? { nil }

    func signIn(email: String, password: String) async throws -> AppUser {
        throw BackendError(message: "Demo mode has no passwords. Pick a sample person instead.")
    }

    func createAccount(name: String, email: String, password: String, role: Role) async throws -> AppUser {
        throw BackendError(message: "Demo mode can't create accounts. Pick a sample person instead.")
    }

    func claimAdmin(code: String) async throws {
        throw BackendError(message: "Demo mode has no administrator code. Pick the sample administrator instead.")
    }

    func requestRole(_ role: Role?, uid: String) async throws {
        guard let i = people.firstIndex(where: { $0.uid == uid }) else { return }
        people[i].requestedRole = role
        people[i].requestedAt = role == nil ? nil : Date()
    }

    func decide(uid: String, role: Role, approve: Bool) async throws {
        guard let i = people.firstIndex(where: { $0.uid == uid }) else { return }
        if approve { people[i].role = role }
        people[i].requestedRole = nil
        people[i].requestedAt = nil
    }

    func deleteAccount(uid: String) async throws {
        people.removeAll { $0.uid == uid }
        for i in sales.indices {
            sales[i].panel = sales[i].panel.filter { $0.value.uid != uid }
        }
    }

    func saveDevice(token: String, uid: String) async throws {}
    func removeDevice(token: String, uid: String) async throws {}

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

    func uploadAttachment(_ data: Data, name: String, contentType: String, to folder: AttachmentFolder,
                          author: String) async throws -> Attachment {
        let path = "\(folder.path)/\(UUID().uuidString)"
        files[path] = data
        return Attachment(name: name, path: path, contentType: contentType, size: data.count)
    }

    func attachmentData(_ attachment: Attachment) async throws -> Data {
        guard let data = files[attachment.path] else {
            throw BackendError(message: "Demo mode only keeps files you attached since the app opened.")
        }
        return data
    }

    func deleteAttachment(_ attachment: Attachment) async throws {
        files[attachment.path] = nil
    }

    func suggestConformation(saleID: String, hip: Int) async throws -> ConformationSuggestion {
        guard hipsBySale[saleID]?.first(where: { $0.number == hip })?.walkVideoURL != nil else {
            throw BackendError(message: "This hip has no walk video yet. Add one on the Sale Walk Video button, save, then try again.")
        }
        try await Task.sleep(for: .seconds(2))
        return ConformationSuggestion(
            grade: 7.0, confidence: "medium",
            summary: "Well balanced with a good shoulder; slightly back at the knee on the left fore.",
            strengths: ["Good length and slope of shoulder", "Strong, well-muscled hindquarter", "Walks straight behind"],
            faults: ["Slightly back at the knee (left fore)", "Toes out a little in front"],
            limits: "Demo mode: this is a sample suggestion, not a real look at the video.",
            frames: 12)
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
