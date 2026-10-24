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

    func loadSale() async throws -> Sale
    func loadHips(saleID: String) async throws -> [Hip]
    func save(hip: Hip, saleID: String) async throws
    func deleteHip(number: Int, saleID: String) async throws
    func upload(_ data: Data, kind: MediaKind, saleID: String, hip: Int) async throws -> URL

    func loadOpinion(saleID: String, hip: Int, slot: OpinionSlot) async throws -> Opinion?
    func save(opinion: Opinion, saleID: String, hip: Int, slot: OpinionSlot) async throws

    func loadPurchases(uid: String) async throws -> Set<String>
    func recordPurchase(uid: String, saleID: String, hip: Int, slot: OpinionSlot) async throws
}

struct BackendError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// In-memory backend with sample data. Nothing is saved between launches.
final class SampleBackend: SaleBackend {
    let isDemo = true
    private var hips = SampleData.hips
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

    func loadSale() async throws -> Sale { SampleData.sale }

    func loadHips(saleID: String) async throws -> [Hip] { hips }

    func save(hip: Hip, saleID: String) async throws {
        if let i = hips.firstIndex(where: { $0.number == hip.number }) { hips[i] = hip } else { hips.append(hip) }
    }

    func deleteHip(number: Int, saleID: String) async throws {
        hips.removeAll { $0.number == number }
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
        if let i = hips.firstIndex(where: { $0.number == hip }), !hips[i].opinionsIn.contains(slot) {
            hips[i].opinionsIn.append(slot)
        }
    }

    func loadPurchases(uid: String) async throws -> Set<String> { purchases[uid] ?? [] }

    func recordPurchase(uid: String, saleID: String, hip: Int, slot: OpinionSlot) async throws {
        purchases[uid, default: []].insert("\(saleID)_\(hip)_\(slot.rawValue)")
    }
}
