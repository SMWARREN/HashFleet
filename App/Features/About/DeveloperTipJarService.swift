import Foundation
import HashFleetCore
import Observation
import StoreKit

/// Identifiers for voluntary developer tip jar tiers.
/// Consumables only - no feature unlock, no subscription, no recurring billing.
public enum DeveloperTipProduct: String, CaseIterable, Identifiable, Sendable {
    case small = "app.hashfleet.tip.small"
    case medium = "app.hashfleet.tip.medium"
    case large = "app.hashfleet.tip.large"
    case supporter = "app.hashfleet.tip.supporter"
    case champion = "app.hashfleet.tip.champion"
    case patron = "app.hashfleet.tip.patron"

    public var id: String { rawValue }

    public var defaultTitle: String {
        switch self {
        case .small: return "Small Tip"
        case .medium: return "Medium Tip"
        case .large: return "Generous Tip"
        case .supporter: return "Supporter Tip"
        case .champion: return "Champion Tip"
        case .patron: return "Patron Tip"
        }
    }

    public var defaultDescription: String {
        switch self {
        case .small: return "Optional developer tip supporting ongoing Hash Fleet maintenance."
        case .medium: return "Optional developer tip supporting continuous improvements."
        case .large: return "Optional developer tip fueling open-source development."
        case .supporter: return "Optional support for development. No feature unlocks."
        case .champion: return "Optional support for development. No feature unlocks."
        case .patron: return "Optional support for development. No feature unlocks."
        }
    }

    public var iconName: String {
        switch self {
        case .small: return "cup.and.saucer"
        case .medium: return "bolt"
        case .large: return "heart.fill"
        case .supporter: return "star.fill"
        case .champion: return "crown.fill"
        case .patron: return "rosette"
        }
    }
}

/// State of a tip jar purchase action.
public enum DeveloperTipPurchaseState: Equatable, Sendable {
    case idle
    case purchasing(String)
    case success(String)
    case pending(String)
    case cancelled
    case failed(String)
}

/// Manages StoreKit 2 consumable tip jar purchases for App Store builds.
/// Verifies transactions before calling `transaction.finish()`, starts a background
/// `Transaction.updates` listener, and guards against concurrent purchase requests with an independent in-flight lock.
/// Strictly filters to approved consumable tip product IDs so unrelated transactions are never finished.
@MainActor
@Observable
public final class DeveloperTipJarService {
    public static let shared = DeveloperTipJarService()

    public private(set) var products: [Product] = []
    public private(set) var isLoadingProducts = false
    public private(set) var hasAttemptedLoad = false
    public private(set) var loadError: String?
    public private(set) var purchaseState: DeveloperTipPurchaseState = .idle

    /// Known set of approved consumable tip product identifiers. Matches Core.
    public static let approvedProductIDs: Set<String> = DeveloperSupport.appStoreTipProductIDs

    /// Independent in-flight purchase lock, distinct from the visible UI state `purchaseState`.
    /// Resetting UI state or receiving out-of-band updates does not allow initiating a concurrent purchase.
    public private(set) var isPurchaseInProgress = false

    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?
    @ObservationIgnored
    private var finishingTransactions: [UInt64: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var finishedTransactionIDs: Set<UInt64> = []

    public init(startUpdatesListener: Bool = true) {
        if startUpdatesListener {
            self.startTransactionUpdatesListener()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Loads products from the App Store using the defined consumable product IDs.
    public func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        loadError = nil
        defer {
            isLoadingProducts = false
            hasAttemptedLoad = true
        }

        let productIDs = DeveloperTipProduct.allCases.map(\.rawValue)
        var lastError: Error?
        var fetched: [Product] = []
        // App Review and fresh sandbox sessions can return a transient error or an
        // empty list on the first request. Retry with backoff before surfacing anything.
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(Double(attempt) * 1.5))
                if Task.isCancelled { return }
            }
            do {
                fetched = try await Product.products(for: productIDs)
                lastError = nil
                if !fetched.isEmpty { break }
            } catch {
                lastError = error
            }
        }
        if fetched.isEmpty, let lastError {
            self.loadError = lastError.localizedDescription
            return
        }

        do {
            // Filter strictly to consumable products belonging to approvedProductIDs
            let validConsumables = fetched.filter { product in
                product.type == .consumable && Self.approvedProductIDs.contains(product.id)
            }
            let idToIndex = Dictionary(uniqueKeysWithValues: productIDs.enumerated().map { ($0.element, $0.offset) })
            self.products = validConsumables.sorted { (idToIndex[$0.id] ?? 0) < (idToIndex[$1.id] ?? 0) }

            // Process any pending unfinished transactions for these products
            await processUnfinishedTransactions()
        }
    }

    /// Initiates a purchase for the given product.
    /// Guards with independent `isPurchaseInProgress` lock, verifies product type is consumable,
    /// verifies transaction before finishing, and finishes via the unified processing pipeline.
    public func purchase(_ product: Product) async {
        guard !isPurchaseInProgress else { return }
        guard Self.approvedProductIDs.contains(product.id), product.type == .consumable else {
            purchaseState = .failed("Unsupported product identifier or non-consumable type.")
            return
        }
        await performPurchase(productID: product.id) {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try self.checkVerified(verification)
                guard transaction.productType == .consumable, transaction.productID == product.id else {
                    return .failed("Transaction type or product mismatch.")
                }
                guard transaction.revocationDate == nil else {
                    return .failed("Transaction has been revoked.")
                }

                await self.processVerifiedTransaction(transaction, isDirectPurchase: true)
                return .success(product.id)

            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending(product.id)
            @unknown default:
                return .failed("An unexpected purchase result was returned.")
            }
        }
    }

    /// The same purchase gate is used by the StoreKit adapter and deterministic tests.
    func performPurchase(
        productID: String,
        operation: @MainActor () async throws -> DeveloperTipPurchaseState
    ) async {
        guard !isPurchaseInProgress, Self.approvedProductIDs.contains(productID) else { return }
        isPurchaseInProgress = true
        purchaseState = .purchasing(productID)
        defer { isPurchaseInProgress = false }
        do {
            purchaseState = try await operation()
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    /// Resets visible purchaseState without unlocking an actively in-flight purchase operation.
    public func resetState() {
        if !isPurchaseInProgress {
            purchaseState = .idle
        }
    }

    /// Background listener for out-of-band completed transactions (e.g. Ask to Buy approvals).
    /// Filters strictly to approved consumable tip product IDs before finishing.
    private func startTransactionUpdatesListener() {
        updatesTask = Task.detached(priority: .utility) { [weak self] in
            for await verification in Transaction.updates {
                guard !Task.isCancelled else { break }
                await self?.handleTransactionVerification(verification, isDirectPurchase: false)
            }
        }
    }

    /// Unified verification handler for transaction updates and unfinished transactions.
    func handleTransactionVerification(_ verification: VerificationResult<Transaction>, isDirectPurchase: Bool) async {
        do {
            let transaction = try checkVerified(verification)
            await processVerifiedTransaction(transaction, isDirectPurchase: isDirectPurchase)
        } catch {
            // Unverified transactions are discarded and never finished
        }
    }

    /// Unified transaction processing pipeline.
    /// Deduplicates concurrent finishes, verifies product type and ID, and avoids clobbering active direct purchases.
    func processVerifiedTransaction(_ transaction: Transaction, isDirectPurchase: Bool) async {
        // Strictly verify consumable type and approved product ID
        guard transaction.productType == .consumable,
              Self.approvedProductIDs.contains(transaction.productID) else {
            return
        }
        // Do not process or finish revoked transactions
        guard transaction.revocationDate == nil else { return }

        await finishTransactionOnce(id: transaction.id) { await transaction.finish() }
        if !isDirectPurchase {
            recordExternalCompletion(productID: transaction.productID)
        }
    }

    /// Duplicate delivery waits for the original finish, rather than reporting success early.
    /// This cache is process-local. StoreKit's unfinished sequence handles relaunch recovery.
    func finishTransactionOnce(id: UInt64, finish: @escaping @MainActor () async -> Void) async {
        if finishedTransactionIDs.contains(id) { return }
        if let existing = finishingTransactions[id] {
            await existing.value
            return
        }
        let task = Task { @MainActor in await finish() }
        finishingTransactions[id] = task
        await task.value
        finishedTransactionIDs.insert(id)
        finishingTransactions[id] = nil
    }

    func recordExternalCompletion(productID: String) {
        guard Self.approvedProductIDs.contains(productID), !isPurchaseInProgress else { return }
        switch purchaseState {
        case .idle:
            purchaseState = .success(productID)
        case .pending(let pendingID) where pendingID == productID:
            purchaseState = .success(productID)
        default:
            break
        }
    }

    /// Processes any unfinished transactions belonging to our approved consumable IDs.
    /// Runs lazily during `loadProducts()` (e.g. when visiting Tip Jar), avoiding startup I/O.
    private func processUnfinishedTransactions() async {
        for await verification in Transaction.unfinished {
            await handleTransactionVerification(verification, isDirectPurchase: false)
        }
    }

    /// Verifies the JWS cryptographic signature of a transaction.
    /// Re-throws an error if verification fails.
    nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
