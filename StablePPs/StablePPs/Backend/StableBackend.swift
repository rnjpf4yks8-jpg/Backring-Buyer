import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

struct BackendError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// What Claude read from a chart: a line for each of your horses that ran, and the ones that didn't.
struct ChartReply: Decodable {
    struct Found: Decodable {
        var horseId: String
        var line: RaceLine
        var profile: Profile?
    }
    struct Missing: Decodable {
        var horseId: String
        var reason: String?
    }
    /// Filled into the horse's empty fields (trainer and owner from the newest chart).
    struct Profile: Decodable {
        var trainer: String?
        var owner: String?
        var color: String?
        var sire: String?
        var dam: String?
        var damSire: String?
        var breeder: String?
        var stateBred: String?
    }
    var lines: [Found]
    var notFound: [Missing]
}

/// What Claude read from a horse's Equibase page: the race it's entered in and its results.
struct EquibasePageReply: Decodable {
    struct PageRace: Decodable {
        var date: String
        var track: String
        var race: Int?
        var finish: Int?
        var speed: Int?
        var earnings: Double?
        var distanceF: Double?
        var surface: String?
        var type: String?
        var classText: String?
        var fieldSize: Int?
    }
    var entry: Entry?
    var noEntryReason: String?
    var races: [PageRace]
}

struct BookPartReply: Decodable {
    var races: [BookRace]
}

/// Firebase for Stable PPs: the same project and sign-in as Backring Buyer. Each person's stable is
/// kept under stables/{uid}, which only they can read or write (firebase/firestore.rules).
final class StableBackend: @unchecked Sendable {
    private let db = Firestore.firestore()

    /// nil until GoogleService-Info.plist is in the app and Firebase is configured.
    static func makeIfConfigured() -> StableBackend? {
        FirebaseApp.app() == nil ? nil : StableBackend()
    }

    // MARK: Account

    /// Calls back with (uid, email) now and whenever someone signs in or out. Returns a stop function.
    func watchAuth(_ onChange: @escaping (String?, String?) -> Void) -> () -> Void {
        let handle = Auth.auth().addStateDidChangeListener { _, user in
            onChange(user?.uid, user?.email)
        }
        return { Auth.auth().removeStateDidChangeListener(handle) }
    }

    func signIn(email: String, password: String) async throws {
        do {
            _ = try await Auth.auth().signIn(withEmail: email.trimmingCharacters(in: .whitespaces), password: password)
        } catch {
            throw Self.plainAuthError(error)
        }
    }

    func createAccount(email: String, password: String) async throws {
        do {
            _ = try await Auth.auth().createUser(withEmail: email.trimmingCharacters(in: .whitespaces), password: password)
        } catch {
            throw Self.plainAuthError(error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespaces))
        } catch {
            throw Self.plainAuthError(error)
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    private func uid() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw BackendError(message: "Sign in first.") }
        return uid
    }

    private func stable() throws -> DocumentReference {
        db.collection("stables").document(try uid())
    }

    private func horses() throws -> CollectionReference {
        try stable().collection("horses")
    }

    private func races(_ horseID: String) throws -> CollectionReference {
        try horses().document(horseID).collection("races")
    }

    private func books() throws -> CollectionReference {
        try stable().collection("books")
    }

    // MARK: Live lists

    func watchHorses(_ onChange: @escaping ([Horse]) -> Void, onError: @escaping (Error) -> Void) -> () -> Void {
        watch(try? horses(), onChange, onError)
    }

    func watchBooks(_ onChange: @escaping ([ConditionBook]) -> Void, onError: @escaping (Error) -> Void) -> () -> Void {
        watch(try? books(), onChange, onError)
    }

    func watchLines(horseID: String, _ onChange: @escaping ([RaceLine]) -> Void,
                    onError: @escaping (Error) -> Void) -> () -> Void {
        watch(try? races(horseID), onChange, onError)
    }

    private func watch<T: Decodable>(_ ref: CollectionReference?, _ onChange: @escaping ([T]) -> Void,
                                     _ onError: @escaping (Error) -> Void) -> () -> Void {
        guard let ref else {
            onError(BackendError(message: "Sign in first."))
            return {}
        }
        let registration = ref.addSnapshotListener { snapshot, error in
            if let error {
                onError(error)
                return
            }
            // A document that doesn't decode (written by something else) is skipped, not fatal.
            let items = (snapshot?.documents ?? []).compactMap { try? $0.data(as: T.self) }
            onChange(items)
        }
        return { registration.remove() }
    }

    // MARK: Writes

    func save(horse: Horse) async throws {
        try await horses().document(horse.id).setData(Firestore.Encoder().encode(horse))
    }

    /// Writes many horses in one go (filling a new stable).
    func save(horses list: [Horse]) async throws {
        let batch = db.batch()
        let ref = try horses()
        for horse in list {
            batch.setData(try Firestore.Encoder().encode(horse), forDocument: ref.document(horse.id))
        }
        try await batch.commit()
    }

    /// Deletes the horse's race lines first, then the horse, so a delete that stops halfway can be run again.
    func delete(horseID: String) async throws {
        let lines = try await races(horseID).getDocuments().documents
        for start in stride(from: 0, to: lines.count, by: 400) {
            let batch = db.batch()
            for doc in lines[start..<min(start + 400, lines.count)] { batch.deleteDocument(doc.reference) }
            try await batch.commit()
        }
        try await horses().document(horseID).delete()
    }

    func lines(horseID: String) async throws -> [RaceLine] {
        try await races(horseID).getDocuments().documents.compactMap { try? $0.data(as: RaceLine.self) }
    }

    func save(line: RaceLine, horseID: String) async throws {
        try await races(horseID).document(line.id).setData(Firestore.Encoder().encode(line))
    }

    func delete(lineID: String, horseID: String) async throws {
        try await races(horseID).document(lineID).delete()
    }

    func save(book: ConditionBook) async throws {
        try await books().document(book.id).setData(Firestore.Encoder().encode(book))
    }

    func delete(bookID: String) async throws {
        try await books().document(bookID).delete()
    }

    // MARK: Claude (Cloud Functions in firebase/functions/stable.js)

    /// Claude reads a chart (PDF or pasted text) and returns a line for each listed horse that ran.
    func readChart(pdf: Data?, text: String?, horses: [Horse]) async throws -> ChartReply {
        var data: [String: Any] = ["horses": horses.map { ["id": $0.id, "name": $0.name] }]
        if let pdf { data["pdf"] = pdf.base64EncodedString() }
        if let text { data["text"] = text }
        return try await callFunction("readChart", data, timeout: 300)
    }

    /// Claude reads text from a horse's Equibase page (copied, or read from the in-app browser).
    func readEquibasePage(text: String, horse: Horse) async throws -> EquibasePageReply {
        try await callFunction("readEquibasePage", ["text": text, "horse": ["id": horse.id, "name": horse.name]], timeout: 200)
    }

    /// Claude reads some pages of a condition book (a small PDF of just those pages).
    func readBookPart(pdf: Data, trackName: String, year: Int, first: Int, last: Int) async throws -> [BookRace] {
        let data: [String: Any] = [
            "pdf": pdf.base64EncodedString(), "trackName": trackName, "year": year, "first": first, "last": last,
        ]
        let reply: BookPartReply = try await callFunction("readConditionBook", data, timeout: 300)
        return reply.races
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
            ? "Reading charts isn’t switched on yet: deploy the Cloud Functions (see StablePPs/README.md)."
            : status == 413
                ? "That file is too big to send. Use the chart for one race or one day."
                : "The server couldn’t do that right now (error \(status)). Try again in a minute.")
    }

    static func plainAuthError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == "FIRAuthErrorDomain" else { return error }
        let message: String? = switch nsError.code {
        case 17004, 17009, 17011:
            "That email and password don’t match an account. Use your Backring Buyer email and password, or tap “Forgot password?”."
        case 17007: "There’s already an account with that email. Tap Sign in instead (or “Forgot password?”)."
        case 17008: "That email address doesn’t look right. Check it and try again."
        case 17026: "Choose a longer password: at least 6 characters."
        case 17010: "Too many tries. Wait a few minutes, or tap “Forgot password?”."
        case 17005: "This account has been switched off."
        case 17020: "No internet connection. Check Wi-Fi or mobile data and try again."
        case 17006: "Email sign-in isn’t switched on in Firebase (Authentication → Sign-in method → Email/Password)."
        default: nil
        }
        return message.map { BackendError(message: $0) } ?? error
    }
}

/// What a callable Cloud Function sends back: {"result": …} or {"error": {"message": …}}.
private struct CallableReply<T: Decodable>: Decodable {
    struct Failure: Decodable { var message: String }
    var result: T?
    var error: Failure?
}
