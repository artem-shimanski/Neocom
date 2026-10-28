import AssetsKit
import BusinessKit
import ESIKit
import Foundation
import Observation

/// A corporation's contracts, as seen by one of its characters, and the items and bids of each
/// one on demand.
///
/// The only owner of `/corporations/{id}/contracts`, `/corporations/{id}/contracts/{contract_id}/items`
/// and `/corporations/{id}/contracts/{contract_id}/bids`. Cached per viewing character, with the
/// corporation id in the kind. Nothing here reaches notifications or widgets.
@Observable
@MainActor
final class CorporationContractsSheet {
    private static let ttl: TimeInterval = 300
    /// Items never change once a contract is issued.
    private static let itemsTTL: TimeInterval = 30 * 86_400
    private static let bidsTTL: TimeInterval = 300
    /// Per-contract files older than this are deleted on init: finished contracts leave the
    /// list after 30 days.
    private static let perContractRetention: TimeInterval = 35 * 86_400
    private static let perContractPrefix = "corp-contract-"

    /// The viewer.
    let characterID: Int64
    let boundCorporationID: Int64
    /// Whether the account was granted `esi-contracts.read_corporation_contracts.v1`.
    let hasScope: Bool
    private(set) var snapshot: ESISnapshot<ESIContracts>

    var corporationID: Int64? { boundCorporationID }
    var value: ESIContracts? { snapshot.value }
    var fetchedAt: Date? { snapshot.fetchedAt }
    var state: ESISnapshot<ESIContracts>.State { snapshot.state }

    var access: BusinessAccess { .corporation(hasScope: hasScope, isForbidden: snapshot.state.isForbidden) }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private let memory: LookupMemory
    @ObservationIgnored private var itemSnapshots: [Int64: ESISnapshot<[ContractItem]>] = [:]
    @ObservationIgnored private var bidSnapshots: [Int64: ESISnapshot<ESIContractBids>] = [:]

    init(characterID: Int64, corporationID: Int64, client: Client, hasScope: Bool) {
        self.characterID = characterID
        self.boundCorporationID = corporationID
        self.client = client
        self.hasScope = hasScope
        let memory = LookupMemory()
        self.memory = memory
        let cache = ESICache()
        cache.removeFiles(of: .character(characterID), prefix: Self.perContractPrefix,
                          writtenBefore: Date.now.addingTimeInterval(-Self.perContractRetention))
        snapshot = ESISnapshot(kind: "corp-\(corporationID)-contracts", characterID: characterID, ttl: Self.ttl, cache: cache) {
            let payload = try await ESIParallel.allPages { page in
                let answer = try await client.corporationContracts(corporationID: corporationID, page: page)
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
    }

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
        let corporationID = boundCorporationID
        let snapshot = ESISnapshot<[ContractItem]>(kind: "\(Self.perContractPrefix)\(corporationID)-items-\(contractID)",
                                                   characterID: characterID, ttl: Self.itemsTTL, cache: ESICache()) {
            try await client.corporationContractItems(corporationID: corporationID, contractID: contractID)
                .map(ContractItem.init)
        }
        itemSnapshots[contractID] = snapshot
        return snapshot
    }

    /// The bids on one auction; the same snapshot for the same contract on every call. For a
    /// non-auction contract ESI returns an empty list or an error.
    func bids(of contractID: Int64) -> ESISnapshot<ESIContractBids> {
        if let snapshot = bidSnapshots[contractID] { return snapshot }
        let client = client
        let corporationID = boundCorporationID
        let memory = memory
        let snapshot = ESISnapshot<ESIContractBids>(kind: "\(Self.perContractPrefix)\(corporationID)-bids-\(contractID)",
                                                    characterID: characterID, ttl: Self.bidsTTL, cache: ESICache()) {
            let payload = try await ESIParallel.allPages { page in
                let answer = try await client.corporationContractBids(corporationID: corporationID, contractID: contractID, page: page)
                return (answer.bids, answer.pages)
            }
            var seen: Set<Int64> = []
            let bids = payload.map(ContractBid.init).filter { seen.insert($0.id).inserted }
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

extension CorporationContractsSheet: ContractsSource, CorporationBound {}

nonisolated extension Contract {
    init(_ payload: Components.Schemas.CorporationsCorporationIdContractsGetPayload) {
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
    init(_ payload: Components.Schemas.CorporationsCorporationIdContractsContractIdItemsGetPayload) {
        self.init(id: payload.recordId,
                  typeID: payload.typeId,
                  quantity: payload.quantity,
                  rawQuantity: payload.rawQuantity,
                  isIncluded: payload.isIncluded,
                  isSingleton: payload.isSingleton)
    }
}

nonisolated extension ContractBid {
    init(_ payload: Components.Schemas.CorporationsCorporationIdContractsContractIdBidsGetPayload) {
        self.init(id: payload.bidId, bidderID: payload.bidderId, amount: payload.amount, date: payload.dateBid)
    }
}
