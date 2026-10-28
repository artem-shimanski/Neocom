import BusinessKit
import Foundation

/// Whether a data source can be read.
enum BusinessAccess: Hashable {
    case granted
    /// The account lacks the scope, or ESI answered `403` for a character route.
    case missingScope
    /// ESI answered `403` to a corporation route: the character's roles don't allow it.
    case forbidden

    /// Access of a corporation route.
    static func corporation(hasScope: Bool, isForbidden: Bool) -> BusinessAccess {
        if !hasScope { return .missingScope }
        return isForbidden ? .forbidden : .granted
    }
}

/// Whose data a screen shows.
enum DataScope: Hashable {
    case character
    case corporation
}

/// What the Assets screens read: a character's or a corporation's assets.
@MainActor
protocol AssetsSource: AnyObject, Sendable {
    /// The viewing character.
    var characterID: Int64 { get }
    /// `nil` for a character's own assets.
    var corporationID: Int64? { get }
    var value: ESIAssets? { get }
    var fetchedAt: Date? { get }
    var state: ESISnapshot<ESIAssets>.State { get }
    var revision: Int { get }
    var progress: AssetsLoadProgress? { get }
    var access: BusinessAccess { get }
    func ensureFresh() async
    func refresh() async
    func resolveTypeNames(missing: Set<Int64>) async -> Bool
}

/// What the Market Orders screens read.
@MainActor
protocol OrdersSource: AnyObject, Sendable {
    /// The viewing character.
    var characterID: Int64 { get }
    /// `nil` for a character's own orders.
    var corporationID: Int64? { get }
    var open: ESISnapshot<ESIOrderList> { get }
    var history: ESISnapshot<ESIOrderList> { get }
    var access: BusinessAccess { get }
    func ensureOpenFresh() async
    func ensureFresh() async
    func refresh() async
}

/// What the Industry screens read.
@MainActor
protocol IndustrySource: AnyObject, Sendable {
    /// The viewing character.
    var characterID: Int64 { get }
    /// `nil` for a character's own jobs.
    var corporationID: Int64? { get }
    var snapshot: ESISnapshot<ESIIndustryJobs> { get }
    var value: ESIIndustryJobs? { get }
    var fetchedAt: Date? { get }
    var state: ESISnapshot<ESIIndustryJobs>.State { get }
    var access: BusinessAccess { get }
    func ensureFresh() async
    func refresh() async
}

/// What the Contracts screens read.
@MainActor
protocol ContractsSource: AnyObject, Sendable {
    /// The viewing character.
    var characterID: Int64 { get }
    /// `nil` for a character's own contracts.
    var corporationID: Int64? { get }
    var snapshot: ESISnapshot<ESIContracts> { get }
    var value: ESIContracts? { get }
    var fetchedAt: Date? { get }
    var state: ESISnapshot<ESIContracts>.State { get }
    var access: BusinessAccess { get }
    func ensureFresh() async
    func refresh() async
    func items(of contractID: Int64) -> ESISnapshot<[ContractItem]>
    func bids(of contractID: Int64) -> ESISnapshot<ESIContractBids>
}

/// What the Wallet screens read: a character's wallet or one corporation wallet division.
@MainActor
protocol WalletSource: AnyObject, Sendable {
    /// The viewing character.
    var characterID: Int64 { get }
    /// `nil` for a character's own wallet.
    var corporationID: Int64? { get }
    /// The corporation wallet division, 1...7; `nil` for a character's own wallet.
    var division: Int? { get }
    /// The current balance, if known.
    var balance: Double? { get }
    var journal: ESISnapshot<ESIWalletJournal> { get }
    var transactions: ESISnapshot<ESIWalletTransactions> { get }
    var access: BusinessAccess { get }
    func ensureFresh() async
    func refresh() async
}
