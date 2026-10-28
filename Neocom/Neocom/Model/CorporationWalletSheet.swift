import AssetsKit
import BusinessKit
import ESIKit
import Foundation
import Observation

/// The balances of a corporation's wallet divisions, as stored in `ESICache`.
nonisolated struct ESICorporationWallets: Codable, Sendable, Hashable {
    /// By division, 1...7.
    var balances: [Int: Double]

    var total: Double { balances.values.reduce(0, +) }
}

/// A corporation's wallets, as seen by one of its characters: the division balances, and the
/// journal and market transactions of each division on demand.
///
/// The only owner of `/corporations/{id}/wallets`, `/corporations/{id}/wallets/{division}/journal`
/// and `/corporations/{id}/wallets/{division}/transactions`. Cached per viewing character, with
/// the corporation id in the kind. Nothing reaches widgets.
@Observable
@MainActor
final class CorporationWalletSheet {
    static let divisions = 1...7
    private static let balancesTTL: TimeInterval = 300

    /// The viewer.
    let characterID: Int64
    let boundCorporationID: Int64
    /// Whether the account was granted `esi-wallet.read_corporation_wallets.v1`.
    let hasScope: Bool

    private(set) var balances: ESISnapshot<ESICorporationWallets>

    var corporationID: Int64? { boundCorporationID }

    var access: BusinessAccess {
        .corporation(hasScope: hasScope, isForbidden: balances.state.isForbidden)
    }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private let memory: LookupMemory
    @ObservationIgnored private var divisionSources: [Int: CorporationWalletDivision] = [:]

    init(characterID: Int64, corporationID: Int64, client: Client, hasScope: Bool) {
        self.characterID = characterID
        self.boundCorporationID = corporationID
        self.client = client
        self.hasScope = hasScope
        memory = LookupMemory()
        balances = ESISnapshot(kind: "corp-\(corporationID)-wallets", characterID: characterID,
                               ttl: Self.balancesTTL, cache: ESICache()) {
            var balances: [Int: Double] = [:]
            for wallet in try await client.corporationWallets(corporationID: corporationID) {
                balances[Int(clamping: wallet.division)] = wallet.balance
            }
            return ESICorporationWallets(balances: balances)
        }
    }

    /// One division's journal and transactions; the same object for the same division on every
    /// call. Holds only cached data until `ensureFresh()` is called on it.
    func division(_ number: Int) -> CorporationWalletDivision {
        precondition(Self.divisions.contains(number), "Wallet division out of range")
        if let source = divisionSources[number] { return source }
        let source = CorporationWalletDivision(sheet: self, division: number, client: client, memory: memory)
        divisionSources[number] = source
        return source
    }

    /// The division if it was already created; reads nothing from disk.
    func existingDivision(_ number: Int) -> CorporationWalletDivision? {
        divisionSources[number]
    }

    /// Refreshes the balances if missing or past the TTL; not the divisions.
    func ensureFresh() async {
        guard hasScope else { return }
        await balances.ensureFresh()
    }

    /// Refreshes the balances only, not the divisions.
    func refresh() async {
        guard hasScope else { return }
        await balances.refresh()
    }

    /// Stops all disk writes; called by `AccountStore` when it drops the sheet.
    func invalidate() {
        balances.invalidate()
        divisionSources.values.forEach { $0.invalidate() }
    }
}

extension CorporationWalletSheet: CorporationBound {}

/// One corporation wallet division: its journal and market transactions, 30 days of each.
/// Created and owned by `CorporationWalletSheet`.
@Observable
@MainActor
final class CorporationWalletDivision {
    private static let ttl: TimeInterval = 3600

    let characterID: Int64
    let boundCorporationID: Int64
    let number: Int
    let hasScope: Bool

    private(set) var journal: ESISnapshot<ESIWalletJournal>
    private(set) var transactions: ESISnapshot<ESIWalletTransactions>

    @ObservationIgnored private weak var sheet: CorporationWalletSheet?

    fileprivate init(sheet: CorporationWalletSheet, division: Int, client: Client, memory: LookupMemory) {
        let characterID = sheet.characterID
        let corporationID = sheet.boundCorporationID
        self.characterID = characterID
        self.boundCorporationID = corporationID
        self.number = division
        self.hasScope = sheet.hasScope
        self.sheet = sheet
        let prefix = "corp-\(corporationID)-wallet-\(division)"
        journal = ESISnapshot(kind: "\(prefix)-journal", characterID: characterID, ttl: Self.ttl, cache: ESICache()) {
            try await WalletFetch.journal(memory: memory, client: client) { page in
                let answer = try await client.corporationWalletJournal(corporationID: corporationID, division: division, page: page)
                return (answer.entries.map(WalletJournalEntry.init), answer.pages)
            }
        }
        transactions = ESISnapshot(kind: "\(prefix)-transactions", characterID: characterID, ttl: Self.ttl, cache: ESICache()) {
            try await WalletFetch.transactions(memory: memory, client: client) { fromID in
                try await client.corporationWalletTransactions(corporationID: corporationID, division: division, fromID: fromID)
                    .map(WalletTransaction.init)
            }
        }
        memory.seed(locations: transactions.value?.locations ?? [:],
                    names: (journal.value?.names ?? [:]).merging(transactions.value?.names ?? [:]) { new, _ in new })
    }

    /// The division's balance from the sheet; the newest journal balance until it is loaded.
    var balance: Double? {
        sheet?.balances.value?.balances[number] ?? journal.value?.entries.first?.balance
    }

    var access: BusinessAccess {
        .corporation(hasScope: hasScope,
                     isForbidden: journal.state.isForbidden || transactions.state.isForbidden
                        || (sheet?.balances.state.isForbidden ?? false))
    }

    /// Refreshes both lists if missing or past their TTL.
    func ensureFresh() async {
        guard hasScope else { return }
        async let journal: Void = journal.ensureFresh()
        async let transactions: Void = transactions.ensureFresh()
        _ = await (journal, transactions)
    }

    func refresh() async {
        guard hasScope else { return }
        async let journal: Void = journal.refresh()
        async let transactions: Void = transactions.refresh()
        _ = await (journal, transactions)
    }

    fileprivate func invalidate() {
        journal.invalidate()
        transactions.invalidate()
    }
}

extension CorporationWalletDivision: WalletSource {
    var corporationID: Int64? { boundCorporationID }
    var division: Int? { number }
}

nonisolated extension WalletJournalEntry {
    init(_ payload: Components.Schemas.CorporationsCorporationIdWalletsDivisionJournalGetPayload) {
        self.init(id: payload.id,
                  date: payload.date,
                  refType: payload.refType.rawValue,
                  amount: payload.amount,
                  balance: payload.balance,
                  firstPartyID: payload.firstPartyId,
                  secondPartyID: payload.secondPartyId,
                  contextID: payload.contextId,
                  contextIDType: payload.contextIdType?.rawValue,
                  description: payload.description,
                  reason: payload.reason.flatMap { $0.isEmpty ? nil : $0 },
                  tax: payload.tax,
                  taxReceiverID: payload.taxReceiverId)
    }
}

nonisolated extension WalletTransaction {
    init(_ payload: Components.Schemas.CorporationsCorporationIdWalletsDivisionTransactionsGetPayload) {
        self.init(id: payload.transactionId,
                  date: payload.date,
                  typeID: payload.typeId,
                  quantity: payload.quantity,
                  unitPrice: payload.unitPrice,
                  clientID: payload.clientId,
                  locationID: payload.locationId,
                  isBuy: payload.isBuy,
                  journalRefID: payload.journalRefId)
    }
}
