#if canImport(FirebaseFirestore)
import FirebaseAuth
import FirebaseCore
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
            throw BackendError(message: "This account has no Backring Buyer profile yet. Ask Backring Buyer staff to set it up.")
        }
        return user
    }

    /// Every new account is a buyer (security rules allow only that). Asking to be a vet, bloodstock agent
    /// or staff saves requestedRole; the administrator gets a push notification and approves it.
    func createAccount(name: String, email: String, password: String, role: Role) async throws -> AppUser {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let asked = Role.requestable.contains(role) ? role : nil
        let user = AppUser(uid: result.user.uid, name: name, role: .buyer, email: email,
                           requestedRole: asked, requestedAt: asked == nil ? nil : Date())
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

    /// A new sale is written whole (empty panel, default prices). For an existing sale only the name,
    /// company and date change, so its panel and prices are kept.
    func save(sale: Sale) async throws {
        let ref = db.collection("sales").document(sale.id)
        if try await ref.getDocument().exists {
            try await ref.setData(["name": sale.name, "company": sale.company, "date": sale.date], merge: true)
        } else {
            try ref.setData(from: sale)
        }
    }

    func setFeaturedSale(_ saleID: String) async throws {
        try await db.collection("config").document("app").setData(["currentSale": saleID], merge: true)
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

    /// The AI's conformation grade from the suggestConformation Cloud Function (firebase/functions/conformation.js).
    /// It can take a minute or two: it pulls frames from the video first.
    func suggestConformation(saleID: String, hip: Int) async throws -> ConformationSuggestion {
        try await callFunction("suggestConformation", ["saleId": saleID, "hip": hip], timeout: 300)
    }

    /// The claimStaff Cloud Function (firebase/functions/staff.js) checks the code and sets the role.
    func claimAdmin(code: String) async throws {
        struct Granted: Decodable { var role: String }
        let _: Granted = try await callFunction("claimStaff", ["code": code], timeout: 60)
    }

    func requestRole(_ role: Role?, uid: String) async throws {
        let update: [String: Any] = if let role {
            ["requestedRole": role.rawValue, "requestedAt": FieldValue.serverTimestamp()]
        } else {
            ["requestedRole": FieldValue.delete(), "requestedAt": FieldValue.delete()]
        }
        try await db.collection("users").document(uid).updateData(update)
    }

    /// The onPersonChanged Cloud Function sees lastDecision change and notifies the person.
    func decide(uid: String, role: Role, approve: Bool) async throws {
        var update: [String: Any] = [
            "requestedRole": FieldValue.delete(),
            "requestedAt": FieldValue.delete(),
            "lastDecision": ["role": role.rawValue, "approved": approve, "at": FieldValue.serverTimestamp()],
        ]
        if approve { update["role"] = role.rawValue }
        try await db.collection("users").document(uid).updateData(update)
    }

    /// The deleteAccount Cloud Function (firebase/functions/people.js) also removes the sign-in.
    func deleteAccount(uid: String) async throws {
        struct Deleted: Decodable { var deleted: Bool }
        let _: Deleted = try await callFunction("deleteAccount", ["uid": uid], timeout: 60)
    }

    func saveDevice(token: String, uid: String) async throws {
        try await db.collection("users").document(uid).collection("devices").document(token)
            .setData(["platform": "ios", "updatedAt": FieldValue.serverTimestamp()])
    }

    func removeDevice(token: String, uid: String) async throws {
        try await db.collection("users").document(uid).collection("devices").document(token).delete()
    }

    /// Calls a Firebase callable Cloud Function over HTTPS, signed in as the current user.
    private func callFunction<T: Decodable>(_ name: String, _ data: [String: Any], timeout: TimeInterval) async throws -> T {
        guard let user = Auth.auth().currentUser else { throw BackendError(message: "Sign in first.") }
        guard let projectID = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://us-central1-\(projectID).cloudfunctions.net/\(name)") else {
            throw BackendError(message: "Firebase isn’t set up in this build.")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": data])

        let (body, response) = try await URLSession.shared.data(for: request)
        let reply = try? JSONDecoder().decode(CallableReply<T>.self, from: body)
        if let result = reply?.result { return result }
        if let message = reply?.error?.message { throw BackendError(message: message) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        throw BackendError(message: status == 404
            ? "This feature isn’t switched on yet. Deploy the Cloud Functions (see firebase/README.md)."
            : "The server couldn’t do that right now (error \(status)). Try again in a minute.")
    }

    // MARK: Attachments

    /// Stored with the uploader's uid and a random file name. The app never shares download links:
    /// files are fetched through Storage, so storage.rules decide who can open each one.
    func uploadAttachment(_ data: Data, name: String, contentType: String, to folder: AttachmentFolder,
                          author: String) async throws -> Attachment {
        let ext = contentType == "application/pdf" ? "pdf" : "jpg"
        let path = "\(folder.path)/\(UUID().uuidString).\(ext)"
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        metadata.customMetadata = ["authorUid": author, "name": name]
        _ = try await storage.reference(withPath: path).putDataAsync(data, metadata: metadata)
        return Attachment(name: name, path: path, contentType: contentType, size: data.count)
    }

    func attachmentData(_ attachment: Attachment) async throws -> Data {
        do {
            return try await storage.reference(withPath: attachment.path).data(maxSize: 30 * 1024 * 1024)
        } catch let error as NSError where error.domain == StorageErrorDomain
                    && error.code == StorageErrorCode.unauthorized.rawValue {
            throw BackendError(message: "You don’t have access to this file.")
        }
    }

    func deleteAttachment(_ attachment: Attachment) async throws {
        do {
            try await storage.reference(withPath: attachment.path).delete()
        } catch let error as NSError where error.domain == StorageErrorDomain
                    && error.code == StorageErrorCode.objectNotFound.rawValue {
            // Already gone.
        }
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
        try await db.collection("users").document(uid).updateData(["role": role.rawValue])
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
/// What a callable Cloud Function sends back: {"result": …} or {"error": {"message": …}}.
private struct CallableReply<T: Decodable>: Decodable {
    struct Failure: Decodable { var message: String }
    var result: T?
    var error: Failure?
}
#endif
