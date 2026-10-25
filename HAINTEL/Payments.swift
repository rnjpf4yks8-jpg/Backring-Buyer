import Foundation
import Observation
import StoreKit

/// Proof of an App Store purchase, saved with the purchase record so the server can check it with Apple.
struct PurchaseReceipt {
    let transactionID: String
    let productID: String
    /// The App Store's signed transaction (JWS).
    let signedTransaction: String
}

/// Apple in-app purchase for the paid opinions, charged to the card on the buyer's Apple ID.
/// One consumable product per kind of opinion; each purchase unlocks one opinion on one hip.
@MainActor
@Observable
final class Payments {
    // Create these two consumable in-app purchases in App Store Connect with exactly these product IDs.
    static let vetProductID = "com.example.haintel.vetopinion"
    static let agentProductID = "com.example.haintel.agentopinion"

    private(set) var products: [String: Product] = [:]

    enum Outcome {
        case paid(PurchaseReceipt, Transaction)
        case cancelled
        /// Waiting on Ask to Buy or a bank check. It completes later through `settle`.
        case pending
    }

    static func productID(_ slot: OpinionSlot) -> String { slot.isVet ? vetProductID : agentProductID }

    func product(_ slot: OpinionSlot) -> Product? { products[Payments.productID(slot)] }

    /// The App Store price in the buyer's currency, once products have loaded.
    func displayPrice(_ slot: OpinionSlot) -> String? { product(slot)?.displayPrice }

    func loadProducts() async {
        guard let loaded = try? await Product.products(for: [Payments.vetProductID, Payments.agentProductID]) else { return }
        products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
    }

    /// Shows Apple's purchase sheet (Face ID, card on the Apple ID) for one opinion.
    /// `purchaseID` is remembered until the purchase is recorded, so an interrupted purchase is never lost.
    func purchase(_ slot: OpinionSlot, purchaseID: String) async throws -> Outcome {
        guard AppStore.canMakePayments else {
            throw BackendError(message: "Opinions are paid with the card on your Apple ID. Add a valid card in Settings › your name › Payment & Shipping, then try again.")
        }
        if products.isEmpty { await loadProducts() }
        guard let product = product(slot) else {
            throw BackendError(message: "Purchases aren’t available right now. Try again in a moment.")
        }
        // Remembered by product until the transaction exists, then by transaction.
        Payments.setIntent(purchaseID, for: "product-\(product.id)")
        switch try await product.purchase() {
        case .success(let result):
            let transaction = try Payments.verified(result)
            Payments.setIntent(purchaseID, for: String(transaction.id))
            return .paid(Payments.receipt(transaction, signed: result.jwsRepresentation), transaction)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Records and finishes purchases that completed outside the purchase sheet: Ask to Buy approvals,
    /// and purchases interrupted before they were recorded. Runs at launch and keeps listening.
    func settle(record: @escaping (String, PurchaseReceipt) async -> Bool) async {
        for await result in Transaction.unfinished {
            await handle(result, record: record)
        }
        for await result in Transaction.updates {
            await handle(result, record: record)
        }
    }

    private func handle(_ result: VerificationResult<Transaction>, record: (String, PurchaseReceipt) async -> Bool) async {
        guard let transaction = try? Payments.verified(result) else { return }
        let key = String(transaction.id)
        guard let purchaseID = Payments.intent(for: key) ?? Payments.intent(for: "product-\(transaction.productID)") else {
            return  // Not one we can place; leave it unfinished rather than lose it.
        }
        if await record(purchaseID, Payments.receipt(transaction, signed: result.jwsRepresentation)) {
            Payments.clearIntent(key)
            Payments.clearIntent("product-\(transaction.productID)")
            await transaction.finish()
        }
    }

    func finish(_ transaction: Transaction) async {
        Payments.clearIntent(String(transaction.id))
        Payments.clearIntent("product-\(transaction.productID)")
        await transaction.finish()
    }

    private static func verified(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction): return transaction
        case .unverified: throw BackendError(message: "Apple couldn’t verify this purchase. You haven’t been charged for an unlock.")
        }
    }

    private static func receipt(_ transaction: Transaction, signed: String) -> PurchaseReceipt {
        PurchaseReceipt(transactionID: String(transaction.id), productID: transaction.productID, signedTransaction: signed)
    }

    // Which opinion each in-flight purchase is for, kept on the device until it's recorded.
    private static let intentsKey = "haintel.purchaseIntents"

    private static func intent(for key: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: intentsKey) as? [String: String])?[key]
    }

    private static func setIntent(_ purchaseID: String, for key: String) {
        var all = (UserDefaults.standard.dictionary(forKey: intentsKey) as? [String: String]) ?? [:]
        all[key] = purchaseID
        UserDefaults.standard.set(all, forKey: intentsKey)
    }

    private static func clearIntent(_ key: String) {
        var all = (UserDefaults.standard.dictionary(forKey: intentsKey) as? [String: String]) ?? [:]
        all[key] = nil
        UserDefaults.standard.set(all, forKey: intentsKey)
    }
}
