import AssetsKit
import BusinessKit
import ESIKit
import Foundation
import Observation

/// A wallet's journal as stored in `ESICache`, with the parties named.
nonisolated struct ESIWalletJournal: Codable, Sendable, Hashable {
    /// Newest first, 30 days.
    var entries: [WalletJournalEntry]
    /// Names of the parties, tax receivers and character, corporation or alliance contexts
    /// that could be resolved.
    var names: [Int64: ESIEntityName]
}

/// A wallet's market transactions as stored in `ESICache`, with clients and locations resolved.
nonisolated struct ESIWalletTransactions: Codable, Sendable, Hashable {
    /// Newest first, 30 days.
    var transactions: [WalletTransaction]
    var names: [Int64: ESIEntityName]
    var locations: [Int64: AssetLocationInfo]
}

/// Paging and name resolution shared by the character and corporation wallets.
nonisolated enum WalletFetch {
    /// ESI keeps 30 days of journal and transactions.
    static let window: TimeInterval = 30 * 86_400
    /// Bounds the `from_id` walk; a batch holds up to 2500 transactions.
    private static let maxBatches = 40

    static var cutoff: Date { Date.now.addingTimeInterval(-window) }

    /// All journal pages, deduplicated, limited to the window, newest first.
    static func journal(memory: LookupMemory, client: Client,
                        page: @escaping @Sendable (Int) async throws -> (records: [WalletJournalEntry], pages: Int)) async throws -> ESIWalletJournal {
        let records = try await ESIParallel.allPages(page)
        let cutoff = cutoff
        var seen: Set<Int64> = []
        let entries = records
            .filter { $0.date >= cutoff && seen.insert($0.id).inserted }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id > $1.id }
        let names = await LookupMemory.names(entries.flatMap(partyIDs), memory: memory, client: client)
        return ESIWalletJournal(entries: entries, names: names)
    }

    /// Walks `from_id` back from the newest batch until a batch is empty, adds nothing new, or
    /// reaches past the window. Deduplicated, limited to the window, newest first.
    static func transactions(memory: LookupMemory, client: Client,
                             batch: @Sendable (Int64?) async throws -> [WalletTransaction]) async throws -> ESIWalletTransactions {
        let cutoff = cutoff
        var byID: [Int64: WalletTransaction] = [:]
        var fromID: Int64?
        for _ in 0..<maxBatches {
            let records = try await batch(fromID)
            let new = records.filter { byID[$0.id] == nil }
            guard !new.isEmpty else { break }
            for record in new { byID[record.id] = record }
            guard let oldest = records.min(by: { $0.id < $1.id }), oldest.date >= cutoff, oldest.id > 1 else { break }
            fromID = oldest.id - 1
        }
        let transactions = byID.values
            .filter { $0.date >= cutoff }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id > $1.id }
        async let names = LookupMemory.names(transactions.map(\.clientID), memory: memory, client: client)
        async let locations = LookupMemory.locations(transactions.map(\.locationID), memory: memory, client: client)
        return ESIWalletTransactions(transactions: transactions, names: await names, locations: await locations)
    }

    private static let namedContexts: Set<String> = ["character_id", "corporation_id", "alliance_id"]

    private static func partyIDs(_ entry: WalletJournalEntry) -> [Int64] {
        var ids = [entry.firstPartyID, entry.secondPartyID, entry.taxReceiverID].compactMap(\.self)
        if let context = entry.contextID, let type = entry.contextIDType, namedContexts.contains(type) {
            ids.append(context)
        }
        return ids
    }
}

/// A character's wallet journal and market transactions, 30 days of each.
///
/// The only owner of `/characters/{id}/wallet/journal` and `/characters/{id}/wallet/transactions`.
/// The balance comes from `CharacterSheet`, which owns `/characters/{id}/wallet`.
@Observable
@MainActor
final class WalletSheet {
    private static let ttl: TimeInterval = 3600

    let characterID: Int64
    /// Whether the account was granted `esi-wallet.read_character_wallet.v1`. Fixed for the
    /// sheet's lifetime: a new sign-in creates a new sheet.
    let hasScope: Bool

    private(set) var journal: ESISnapshot<ESIWalletJournal>
    private(set) var transactions: ESISnapshot<ESIWalletTransactions>

    @ObservationIgnored private weak var character: CharacterSheet?
    @ObservationIgnored private let memory: LookupMemory

    init(characterID: Int64, client: Client, hasScope: Bool, character: CharacterSheet) {
        self.characterID = characterID
        self.hasScope = hasScope
        self.character = character
        let memory = LookupMemory()
        self.memory = memory
        journal = ESISnapshot(kind: "wallet-journal", characterID: characterID, ttl: Self.ttl, cache: ESICache()) {
            try await WalletFetch.journal(memory: memory, client: client) { page in
                let answer = try await client.walletJournal(characterID: characterID, page: page)
                return (answer.entries.map(WalletJournalEntry.init), answer.pages)
            }
        }
        transactions = ESISnapshot(kind: "wallet-transactions", characterID: characterID, ttl: Self.ttl, cache: ESICache()) {
            try await WalletFetch.transactions(memory: memory, client: client) { fromID in
                try await client.walletTransactions(characterID: characterID, fromID: fromID).map(WalletTransaction.init)
            }
        }
        memory.seed(locations: transactions.value?.locations ?? [:],
                    names: (journal.value?.names ?? [:]).merging(transactions.value?.names ?? [:]) { new, _ in new })
    }

    /// The profile's balance; the newest journal balance until the profile is loaded.
    var balance: Double? {
        character?.profile?.balance ?? journal.value?.entries.first?.balance
    }

    /// The account lacks the scope, or ESI answered `403` (a token issued before the scope was
    /// requested).
    var isMissingScope: Bool {
        !hasScope || journal.state.isForbidden || transactions.state.isForbidden
    }

    /// Refreshes both lists if missing or past their TTL.
    func ensureFresh() async {
        guard hasScope else { return }
        async let journal: Void = journal.ensureFresh()
        async let transactions: Void = transactions.ensureFresh()
        _ = await (journal, transactions)
    }

    /// Refreshes the journal alone if missing or past its TTL: the Home tile's figures.
    func ensureJournalFresh() async {
        guard hasScope else { return }
        await journal.ensureFresh()
    }

    func refresh() async {
        guard hasScope else { return }
        async let journal: Void = journal.refresh()
        async let transactions: Void = transactions.refresh()
        _ = await (journal, transactions)
    }

    /// Stops all disk writes; called by `AccountStore` when it drops the sheet.
    func invalidate() {
        journal.invalidate()
        transactions.invalidate()
    }
}

extension WalletSheet: WalletSource {
    var corporationID: Int64? { nil }
    var division: Int? { nil }
    var access: BusinessAccess { isMissingScope ? .missingScope : .granted }
}

nonisolated extension WalletJournalEntry {
    init(_ payload: Components.Schemas.CharactersCharacterIdWalletJournalGetPayload) {
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
    init(_ payload: Components.Schemas.CharactersCharacterIdWalletTransactionsGetPayload) {
        self.init(id: payload.transactionId,
                  date: payload.date,
                  typeID: payload.typeId,
                  quantity: payload.quantity,
                  unitPrice: payload.unitPrice,
                  clientID: payload.clientId,
                  locationID: payload.locationId,
                  isBuy: payload.isBuy,
                  isPersonal: payload.isPersonal,
                  journalRefID: payload.journalRefId)
    }
}
