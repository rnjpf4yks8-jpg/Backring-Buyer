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

    /// Saves the role the person picked. Anything but buyer waits for staff to approve it (firestore.rules enforces this).
    func createAccount(name: String, email: String, password: String, role: Role) async throws -> AppUser {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let user = AppUser(uid: result.user.uid, name: name, role: role, email: email,
                           status: role.needsApproval ? .pending : .approved)
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

    func loadSales() async throws -> [Sale] {
        let snap = try await db.collection("sales").getDocuments()
        return try snap.documents.map { doc in
            var sale = try doc.data(as: Sale.self)
            sale.id = doc.documentID
            return sale
        }
    }

    func featuredSaleID() async throws -> String? {
        try await db.collection("config").document("app").getDocument().get("currentSale") as? String
    }

    func hipCount(saleID: String) async throws -> Int {
        let result = try await hipsRef(saleID).count.getAggregation(source: .server)
        return result.count.intValue
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

    /// Writes the opinion as pending and moves it to the hip's approval queue, in one batch.
    func save(opinion: Opinion, saleID: String, hip: Int, slot: OpinionSlot) async throws {
        var pending = opinion
        pending.status = .pending
        let batch = db.batch()
        try batch.setData(from: pending, forDocument: opinionRef(saleID, hip, slot))
        batch.updateData(["opinionsIn": FieldValue.arrayRemove([slot.rawValue]),
                          "opinionsPending": FieldValue.arrayUnion([slot.rawValue])],
                         forDocument: hipsRef(saleID).document(String(hip)))
        try await batch.commit()
    }

    func review(approve: Bool, saleID: String, hip: Int, slot: OpinionSlot) async throws {
        let batch = db.batch()
        batch.updateData(["status": (approve ? OpinionStatus.approved : .rejected).rawValue],
                         forDocument: opinionRef(saleID, hip, slot))
        batch.updateData(["opinionsPending": FieldValue.arrayRemove([slot.rawValue]),
                          "opinionsIn": approve ? FieldValue.arrayUnion([slot.rawValue]) : FieldValue.arrayRemove([slot.rawValue])],
                         forDocument: hipsRef(saleID).document(String(hip)))
        try await batch.commit()
    }

    // MARK: People and panels (staff)

    func loadPeople() async throws -> [AppUser] {
        let snap = try await db.collection("users").getDocuments()
        return try snap.documents.map { try $0.data(as: AppUser.self) }
    }

    func setRole(_ role: Role, uid: String) async throws {
        try await db.collection("users").document(uid).updateData(["role": role.rawValue,
                                                                   "status": AccountStatus.approved.rawValue])
    }

    func rejectAccount(uid: String) async throws {
        try await db.collection("users").document(uid).updateData(["status": AccountStatus.rejected.rawValue])
    }

    /// Replaces the sale's whole panel, so a cleared slot is removed.
    func savePanel(_ panel: [String: PanelMember], saleID: String) async throws {
        let encoded = try panel.mapValues { try Firestore.Encoder().encode($0) }
        try await db.collection("sales").document(saleID).updateData(["panel": encoded])
    }

    // MARK: Purchases

    func loadPurchases(uid: String) async throws -> Set<String> {
        let snap = try await db.collection("users").document(uid).collection("purchases").getDocuments()
        return Set(snap.documents.map(\.documentID))
    }

    /// Saves the App Store purchase with its signed transaction. The verifyPurchase Cloud Function checks
    /// it with Apple and deletes the record if it isn't a real, unused purchase of the right product.
    func recordPurchase(uid: String, purchaseID: String, receipt: PurchaseReceipt?) async throws {
        var data: [String: Any] = ["createdAt": FieldValue.serverTimestamp()]
        if let receipt {
            data["transactionId"] = receipt.transactionID
            data["productId"] = receipt.productID
            data["signedTransaction"] = receipt.signedTransaction
        }
        try await db.collection("users").document(uid).collection("purchases").document(purchaseID).setData(data)
    }

    private func hipsRef(_ saleID: String) -> CollectionReference {
        db.collection("sales").document(saleID).collection("hips")
    }

    private func opinionRef(_ saleID: String, _ hip: Int, _ slot: OpinionSlot) -> DocumentReference {
        hipsRef(saleID).document(String(hip)).collection("opinions").document(slot.rawValue)
    }
}
#endif
