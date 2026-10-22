import AssetsKit
import BusinessKit
import ESIKit
import Foundation
import Observation

/// A character's contracts (active and 30 days of finished) as stored in `ESICache`, with
/// locations and parties resolved.
nonisolated struct ESIContracts: Codable, Sendable, Hashable {
    var contracts: [Contract]
    /// Names of the `startLocationID`s and `endLocationID`s that could be resolved.
    var locations: [Int64: AssetLocationInfo]
    /// Names of issuers, issuer corporations, assignees and acceptors that could be resolved.
    /// An assignee can be a corporation or an alliance (`ESIEntityName.category`).
    var names: [Int64: ESIEntityName]
}

/// The bids on one auction, with bidder names.
nonisolated struct ESIContractBids: Codable, Sendable, Hashable {
    var bids: [ContractBid]
    var names: [Int64: ESIEntityName]
}

/// A character's contracts, and the items and bids of each one on demand.
///
/// The only owner of `/characters/{id}/contracts`, `/contracts/{contract_id}/items` and
/// `/contracts/{contract_id}/bids`. Per-contract snapshots are created on first request and
/// kept for the sheet's lifetime.
@Observable
@MainActor
final class ContractsSheet {
    private static let ttl: TimeInterval = 300
    /// Items never change once a contract is issued.
    private static let itemsTTL: TimeInterval = 30 * 86_400
    private static let bidsTTL: TimeInterval = 300
    /// Per-contract files older than this are deleted on init: finished contracts leave the
    /// list after 30 days.
    private static let perContractRetention: TimeInterval = 35 * 86_400
    private static let perContractPrefix = "contract-"

    nonisolated static let cacheKind = "contracts"

    let characterID: Int64
    /// Whether the account was granted `esi-contracts.read_character_contracts.v1`.
    let hasScope: Bool
    private(set) var snapshot: ESISnapshot<ESIContracts>

    var value: ESIContracts? { snapshot.value }
    var fetchedAt: Date? { snapshot.fetchedAt }
    var state: ESISnapshot<ESIContracts>.State { snapshot.state }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private let memory: LookupMemory
    @ObservationIgnored private var itemSnapshots: [Int64: ESISnapshot<[ContractItem]>] = [:]
    @ObservationIgnored private var bidSnapshots: [Int64: ESISnapshot<ESIContractBids>] = [:]

    init(characterID: Int64, client: Client, hasScope: Bool) {
        self.characterID = characterID
        self.client = client
        self.hasScope = hasScope
        let memory = LookupMemory()
        self.memory = memory
        let cache = ESICache()
        cache.removeFiles(of: .character(characterID), prefix: Self.perContractPrefix,
                          writtenBefore: Date.now.addingTimeInterval(-Self.perContractRetention))
        snapshot = ESISnapshot(kind: Self.cacheKind, characterID: characterID, ttl: Self.ttl, cache: cache) {
            let payload = try await ESIParallel.allPages { page in
                let answer = try await client.contracts(characterID: characterID, page: page)
                return (answer.contracts, answer.pages)
            }
            var seen: Set<Int64> = []
            let contracts = payload.map(Contract.init).filter { seen.insert($0.id).inserted }
            async let locations = LookupMemory.locations(contracts.flatMap { [$0.startLocationID ?? 0, $0.endLocationID ?? 0] },
                                                         memory: memory, client: client)
            async let names = LookupMemory.names(contracts.flatMap { [$0.issuerID, $0.issuerCorporationID, $0.assigneeID, $0.acceptorID] },
                                                 memory: memory, client: client)
            return ESIContracts(contracts: contracts, locations: await locations, names: await names)
        }
        memory.seed(locations: snapshot.value?.locations ?? [:], names: snapshot.value?.names ?? [:])
        // A new contract list reschedules the expiry and deadline notifications.
        snapshot.didUpdate = { _ in
            NotificationPlanner.shared.reschedule(.contracts, characterID: characterID)
        }
    }

    /// The account lacks the scope, or ESI answered `403`.
    var isMissingScope: Bool { !hasScope || snapshot.state.isForbidden }

    /// Refreshes the list if missing or past the TTL.
    func ensureFresh() async {
        guard hasScope else { return }
        await snapshot.ensureFresh()
    }

    /// Refreshes the list only, not the per-contract snapshots.
    func refresh() async {
        guard hasScope else { return }
        await snapshot.refresh()
    }

    /// The items of one contract; the same snapshot for the same contract on every call.
    /// Holds only cached data until `ensureFresh()` is called on it.
    func items(of contractID: Int64) -> ESISnapshot<[ContractItem]> {
        if let snapshot = itemSnapshots[contractID] { return snapshot }
        let client = client
        let characterID = characterID
        let snapshot = ESISnapshot<[ContractItem]>(kind: "\(Self.perContractPrefix)items-\(contractID)",
                                                   characterID: characterID, ttl: Self.itemsTTL, cache: ESICache()) {
            try await client.contractItems(characterID: characterID, contractID: contractID).map(ContractItem.init)
        }
        itemSnapshots[contractID] = snapshot
        return snapshot
    }

    /// The bids on one auction; the same snapshot for the same contract on every call. For a
    /// non-auction contract ESI returns an empty list or an error.
    func bids(of contractID: Int64) -> ESISnapshot<ESIContractBids> {
        if let snapshot = bidSnapshots[contractID] { return snapshot }
        let client = client
        let characterID = characterID
        let memory = memory
        let snapshot = ESISnapshot<ESIContractBids>(kind: "\(Self.perContractPrefix)bids-\(contractID)",
                                                    characterID: characterID, ttl: Self.bidsTTL, cache: ESICache()) {
            let bids = try await client.contractBids(characterID: characterID, contractID: contractID).map(ContractBid.init)
            let names = await LookupMemory.names(bids.map(\.bidderID), memory: memory, client: client)
            return ESIContractBids(bids: bids, names: names)
        }
        memory.seed(names: snapshot.value?.names ?? [:])
        bidSnapshots[contractID] = snapshot
        return snapshot
    }

    /// Stops all disk writes; called by `AccountStore` when it drops the sheet.
    func invalidate() {
        snapshot.invalidate()
        itemSnapshots.values.forEach { $0.invalidate() }
        bidSnapshots.values.forEach { $0.invalidate() }
    }
}

nonisolated extension Contract {
    init(_ payload: Components.Schemas.CharactersCharacterIdContractsGetPayload) {
        self.init(id: payload.contractId,
                  type: payload._type.rawValue,
                  status: payload.status.rawValue,
                  availability: payload.availability.rawValue,
                  title: payload.title.flatMap { $0.isEmpty ? nil : $0 },
                  issuerID: payload.issuerId,
                  issuerCorporationID: payload.issuerCorporationId,
                  assigneeID: payload.assigneeId,
                  acceptorID: payload.acceptorId,
                  forCorporation: payload.forCorporation,
                  dateIssued: payload.dateIssued,
                  dateExpired: payload.dateExpired,
                  dateAccepted: payload.dateAccepted,
                  dateCompleted: payload.dateCompleted,
                  daysToComplete: payload.daysToComplete.map(Int.init),
                  price: payload.price,
                  reward: payload.reward,
                  collateral: payload.collateral,
                  buyout: payload.buyout,
                  volume: payload.volume,
                  startLocationID: payload.startLocationId,
                  endLocationID: payload.endLocationId)
    }
}

nonisolated extension ContractItem {
    init(_ payload: Components.Schemas.CharactersCharacterIdContractsContractIdItemsGetPayload) {
        self.init(id: payload.recordId,
                  typeID: payload.typeId,
                  quantity: payload.quantity,
                  rawQuantity: payload.rawQuantity,
                  isIncluded: payload.isIncluded,
                  isSingleton: payload.isSingleton)
    }
}

nonisolated extension ContractBid {
    init(_ payload: Components.Schemas.CharactersCharacterIdContractsContractIdBidsGetPayload) {
        self.init(id: payload.bidId, bidderID: payload.bidderId, amount: payload.amount, date: payload.dateBid)
    }
}
