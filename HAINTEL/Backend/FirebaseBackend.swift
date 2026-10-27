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
///
/// Administrator tools (adding people, deleting sales and opinions) work within the security rules
/// from the app itself, so they need no Cloud Function.
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

    /// Deletes the files first, then the opinions and hips, and the sale itself last, so a delete that
    /// stops halfway can simply be run again. Purchase records stay with the buyers' accounts.
    func deleteSale(_ saleID: String) async throws {
        let hipDocs = try await hipsRef(saleID).getDocuments().documents

        // Every hip's opinions. Returned ones aren't listed on the hip, so each hip is checked.
        var opinionDocs: [QueryDocumentSnapshot] = []
        for start in stride(from: 0, to: hipDocs.count, by: 20) {
            try await withThrowingTaskGroup(of: [QueryDocumentSnapshot].self) { group in
                for hip in hipDocs[start..<min(start + 20, hipDocs.count)] {
                    group.addTask { try await hip.reference.collection("opinions").getDocuments().documents }
                }
                for try await found in group { opinionDocs += found }
            }
        }

        var files: [String] = []
        for doc in hipDocs {
            guard let hip = try? doc.data(as: Hip.self) else { continue }
            files += (hip.vetReport.attachments ?? []).map(\.path)
            // Sale pictures and walk videos uploaded in the app (not Vimeo or YouTube links).
            if hip.photoURL?.host()?.contains("firebasestorage") == true {
                files.append("sales/\(saleID)/hips/\(hip.number)/\(MediaKind.photo.fileName)")
            }
            if hip.walkVideoURL?.host()?.contains("firebasestorage") == true {
                files.append("sales/\(saleID)/hips/\(hip.number)/\(MediaKind.walkVideo.fileName)")
            }
        }
        for doc in opinionDocs {
            files += ((try? doc.data(as: Opinion.self))?.attachments ?? []).map(\.path)
        }
        // A file that won't delete stays in Storage, but nothing points to it any more.
        await deleteFiles(files)

        try await deleteDocuments(opinionDocs.map(\.reference) + hipDocs.map(\.reference))

        let config = db.collection("config").document("app")
        if try await config.getDocument().get("currentSale") as? String == saleID {
            try await config.updateData(["currentSale": FieldValue.delete()])
        }
        try await db.collection("sales").document(saleID).delete()
    }

    private func deleteFiles(_ paths: [String]) async {
        for start in stride(from: 0, to: paths.count, by: 10) {
            await withTaskGroup(of: Void.self) { group in
                for path in paths[start..<min(start + 10, paths.count)] {
                    group.addTask { try? await self.storage.reference(withPath: path).delete() }
                }
            }
        }
    }

    /// 20 deletes per batch: each one's security rule reads the signed-in profile, and a batch may
    /// read at most 20 documents. Up to 8 batches run at once.
    private func deleteDocuments(_ refs: [DocumentReference]) async throws {
        let batches = stride(from: 0, to: refs.count, by: 20).map { Array(refs[$0..<min($0 + 20, refs.count)]) }
        for start in stride(from: 0, to: batches.count, by: 8) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for chunk in batches[start..<min(start + 8, batches.count)] {
                    group.addTask {
                        let batch = self.db.batch()
                        for ref in chunk { batch.deleteDocument(ref) }
                        try await batch.commit()
                    }
                }
                try await group.waitForAll()
            }
        }
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

    /// New hips are written whole; hips already in the sale get only the spreadsheet's fields, so
    /// opinions, media and staff edits are kept. Written in batches (Firestore allows 500 per batch).
    func importCatalog(_ rows: [CatalogImport.Row], saleID: String) async throws -> (added: Int, updated: Int) {
        let existing = Set(try await hipsRef(saleID).getDocuments().documents.map(\.documentID))
        var added = 0, updated = 0
        for start in stride(from: 0, to: rows.count, by: 400) {
            let batch = db.batch()
            for row in rows[start..<min(start + 400, rows.count)] {
                let ref = hipsRef(saleID).document(String(row.number))
                if existing.contains(ref.documentID) {
                    let fields = CatalogImport.fieldUpdates(row)
                    if !fields.isEmpty { batch.updateData(fields, forDocument: ref) }
                    updated += 1
                } else {
                    try batch.setData(from: CatalogImport.newHip(row), forDocument: ref)
                    added += 1
                }
            }
            try await batch.commit()
        }
        return (added, updated)
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

    /// Security rules let a person create only their own profile, as a buyer. So the new sign-in is made on a
    /// second copy of Firebase that signs in as them (the administrator stays signed in here), writes their
    /// buyer profile as them, and then the administrator gives them their role.
    func addPerson(name: String, email: String, role: Role, password: String?) async throws -> AppUser {
        let helper = try await Self.helperApp()
        let helperAuth = Auth.auth(app: helper)
        let typed = (password ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await helperAuth.createUser(withEmail: email,
                                                     password: typed.isEmpty ? Self.randomPassword() : typed)
        defer { try? helperAuth.signOut() }

        var person = AppUser(uid: result.user.uid, name: name, role: .buyer, email: email)
        do {
            try await Firestore.firestore(app: helper).collection("users").document(person.uid)
                .setData(Firestore.Encoder().encode(person))
        } catch {
            // Don't leave a sign-in with no profile behind.
            try? await result.user.delete()
            throw error
        }
        if role != .buyer {
            try await db.collection("users").document(person.uid).updateData(["role": role.rawValue])
            person.role = role
        }
        if typed.isEmpty { try await Auth.auth().sendPasswordReset(withEmail: email) }
        return person
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    /// The second Firebase app addPerson signs in on. Made once, on the main thread.
    @MainActor private static func helperApp() throws -> FirebaseApp {
        let name = "addPerson"
        if let app = FirebaseApp.app(name: name) { return app }
        guard let options = FirebaseApp.app()?.options else {
            throw BackendError(message: "Firebase isn’t set up in this build.")
        }
        FirebaseApp.configure(name: name, options: options)
        guard let app = FirebaseApp.app(name: name) else {
            throw BackendError(message: "Couldn’t get ready to add people. Try again.")
        }
        return app
    }

    /// Never shown to anyone: the person picks their own password from the emailed link.
    private static func randomPassword() -> String {
        "\(UUID().uuidString)-\(UUID().uuidString)"
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

    /// Writes the opinion and, in the same batch, moves its slot on the hip: to the approval queue
    /// (pending), or straight to opinionsIn when staff approve it as they post it.
    func save(opinion: Opinion, saleID: String, hip: Int, slot: OpinionSlot, approved: Bool) async throws {
        var saved = opinion
        saved.status = approved ? .approved : .pending
        let value = [slot.rawValue]
        let moves: [String: Any] = approved
            ? ["opinionsIn": FieldValue.arrayUnion(value), "opinionsPending": FieldValue.arrayRemove(value)]
            : ["opinionsIn": FieldValue.arrayRemove(value), "opinionsPending": FieldValue.arrayUnion(value)]
        let batch = db.batch()
        try batch.setData(from: saved, forDocument: opinionRef(saleID, hip, slot))
        batch.updateData(moves, forDocument: hipsRef(saleID).document(String(hip)))
        try await batch.commit()
    }

    func deleteOpinion(saleID: String, hip: Int, slot: OpinionSlot) async throws {
        let value = [slot.rawValue]
        let batch = db.batch()
        batch.deleteDocument(opinionRef(saleID, hip, slot))
        batch.updateData(["opinionsIn": FieldValue.arrayRemove(value), "opinionsPending": FieldValue.arrayRemove(value)],
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
