#if canImport(FirebaseFirestore)
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation

/// Firestore layout (see firebase/README.md):
///   config/app                               { currentSale, testPurchases }
///   users/{uid}                              AppUser
///   users/{uid}/purchases/{sale_hip_slot}    { createdAt }
///   sales/{saleID}                           Sale
///   sales/{saleID}/hips/{hipNumber}          Hip
///   sales/{saleID}/hips/{hipNumber}/opinions/{slot}   Opinion
final class FirebaseBackend: SaleBackend {
    let isDemo = false
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    // MARK: Account

    func currentUser() async throws -> AppUser? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return try await loadUser(uid)
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        guard let user = try await loadUser(result.user.uid) else {
            throw BackendError(message: "This account has no HAINTEL profile yet. Ask HAINTEL staff to set it up.")
        }
        return user
    }

    /// New accounts are always buyers. Staff change the role in Firestore for staff, vets and agents.
    func createAccount(name: String, email: String, password: String) async throws -> AppUser {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let user = AppUser(uid: result.user.uid, name: name, role: .buyer)
        try db.collection("users").document(user.uid).setData(from: user)
        return user
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    private func loadUser(_ uid: String) async throws -> AppUser? {
        let snap = try await db.collection("users").document(uid).getDocument()
        return snap.exists ? try snap.data(as: AppUser.self) : nil
    }

    // MARK: Sale and hips

    func loadSale() async throws -> Sale {
        let config = try await db.collection("config").document("app").getDocument()
        guard let saleID = config.get("currentSale") as? String else {
            throw BackendError(message: "No current sale is set. Set config/app.currentSale in Firestore.")
        }
        return try await db.collection("sales").document(saleID).getDocument(as: Sale.self)
    }

    func loadHips(saleID: String) async throws -> [Hip] {
        let snap = try await hipsRef(saleID).getDocuments()
        return try snap.documents.map { try $0.data(as: Hip.self) }
    }

    func save(hip: Hip, saleID: String) async throws {
        try hipsRef(saleID).document(String(hip.number)).setData(from: hip)
    }

    func deleteHip(number: Int, saleID: String) async throws {
        try await hipsRef(saleID).document(String(number)).delete()
    }

    func upload(_ data: Data, kind: MediaKind, saleID: String, hip: Int) async throws -> URL {
        let ref = storage.reference().child("sales/\(saleID)/hips/\(hip)/\(kind.fileName)")
        let metadata = StorageMetadata()
        metadata.contentType = kind.contentType
        _ = try await ref.putDataAsync(data, metadata: metadata)
        return try await ref.downloadURL()
    }

    // MARK: Opinions

    func loadOpinion(saleID: String, hip: Int, slot: OpinionSlot) async throws -> Opinion? {
        let snap = try await opinionRef(saleID, hip, slot).getDocument()
        return snap.exists ? try snap.data(as: Opinion.self) : nil
    }

    /// Writes the opinion and marks it as posted on the hip, in one batch.
    func save(opinion: Opinion, saleID: String, hip: Int, slot: OpinionSlot) async throws {
        let batch = db.batch()
        try batch.setData(from: opinion, forDocument: opinionRef(saleID, hip, slot))
        batch.updateData(["opinionsIn": FieldValue.arrayUnion([slot.rawValue])],
                         forDocument: hipsRef(saleID).document(String(hip)))
        try await batch.commit()
    }

    // MARK: Purchases

    func loadPurchases(uid: String) async throws -> Set<String> {
        let snap = try await db.collection("users").document(uid).collection("purchases").getDocuments()
        return Set(snap.documents.map(\.documentID))
    }

    /// Test purchases only: the security rules allow this while config/app.testPurchases is true.
    /// For launch, replace with StoreKit and a Cloud Function that verifies the receipt and writes this doc.
    func recordPurchase(uid: String, saleID: String, hip: Int, slot: OpinionSlot) async throws {
        try await db.collection("users").document(uid).collection("purchases")
            .document("\(saleID)_\(hip)_\(slot.rawValue)")
            .setData(["createdAt": FieldValue.serverTimestamp()])
    }

    private func hipsRef(_ saleID: String) -> CollectionReference {
        db.collection("sales").document(saleID).collection("hips")
    }

    private func opinionRef(_ saleID: String, _ hip: Int, _ slot: OpinionSlot) -> DocumentReference {
        hipsRef(saleID).document(String(hip)).collection("opinions").document(slot.rawValue)
    }
}
#endif
