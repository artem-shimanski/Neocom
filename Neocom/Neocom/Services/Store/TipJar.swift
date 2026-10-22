import Foundation
import Observation
import StoreKit

/// The only owner of StoreKit: loads the tip products, buys them and finishes their transactions.
///
/// Created once at launch so that `Transaction.updates` is observed from the start; interrupted
/// or approval-pending tips are delivered and finished there. Tips unlock nothing, so a verified
/// transaction is simply finished.
@Observable
@MainActor
final class TipJar {
    /// A tip on offer: its place on screen and the StoreKit product.
    struct Tip: Identifiable {
        let tier: TipConfiguration.Tier
        let product: Product
        var id: String { tier.productID }
    }

    enum Availability: Equatable {
        case loading
        /// At least one of the configured products is in the store.
        case available
        /// The store could not be reached, or knows none of the products.
        case unavailable
    }

    enum PurchaseOutcome {
        case thanked
        /// The buyer closed the sheet.
        case cancelled
        /// Waiting for approval (Ask to Buy, a payment check); delivered later through
        /// `Transaction.updates`, if at all.
        case pending
        /// The purchase failed, or its transaction did not verify.
        case failed
    }

    private(set) var availability: Availability = .loading
    /// The tiles' tips in `TipConfiguration.tiles` order; tiers missing from the store are omitted.
    private(set) var tiles: [Tip] = []
    /// The More menu's tips in `TipConfiguration.more` order.
    private(set) var more: [Tip] = []
    private(set) var isPurchasing = false

    @ObservationIgnored private var updates: Task<Void, Never>?
    /// The fetch in flight; owned here so that a cancelled caller does not make the store
    /// `.unavailable`.
    @ObservationIgnored private var loading: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.settle(result)
            }
        }
    }

    /// Loads the products unless already loaded; an unavailable store is queried again.
    func loadIfNeeded() async {
        guard availability != .available else { return }
        await load()
    }

    /// Fetches the products; a concurrent caller waits for the fetch in flight.
    func load() async {
        if let loading {
            await loading.value
            return
        }
        availability = .loading
        let task = Task { await fetch() }
        loading = task
        await task.value
        loading = nil
    }

    private func fetch() async {
        do {
            let products = try await Product.products(for: TipConfiguration.allProductIDs)
            let byID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            tiles = TipConfiguration.tiles.compactMap { tier in byID[tier.productID].map { Tip(tier: tier, product: $0) } }
            more = TipConfiguration.more.compactMap { tier in byID[tier.productID].map { Tip(tier: tier, product: $0) } }
            availability = tiles.isEmpty && more.isEmpty ? .unavailable : .available
        } catch {
            tiles = []
            more = []
            availability = .unavailable
        }
    }

    /// Buys `tip` through `purchase` (SwiftUI's `PurchaseAction`, which knows the scene to present
    /// in) and finishes the transaction when it verifies.
    func purchase(_ tip: Tip,
                  using purchase: (Product) async throws -> Product.PurchaseResult) async -> PurchaseOutcome {
        guard !isPurchasing else { return .cancelled }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await purchase(tip.product) {
            case let .success(verification):
                return await settle(verification) ? .thanked : .failed
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed
        }
    }

    /// Finishes a verified transaction and returns whether it verified; an unverified one is left alone.
    @discardableResult
    private func settle(_ verification: VerificationResult<Transaction>) async -> Bool {
        guard case let .verified(transaction) = verification else { return false }
        await transaction.finish()
        return true
    }
}
