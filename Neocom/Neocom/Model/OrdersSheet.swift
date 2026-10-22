import AssetsKit
import BusinessKit
import ESIKit
import Foundation
import Observation

/// A character's orders as stored in `ESICache`, with their locations resolved.
nonisolated struct ESIOrderList: Codable, Sendable, Hashable {
    var orders: [CharacterOrder]
    /// Names of the `locationID`s of `orders` that could be resolved.
    var locations: [Int64: AssetLocationInfo]
}

/// A character's own market orders: the open ones and 90 days of history.
///
/// The only owner of `/characters/{id}/orders` and `/characters/{id}/orders/history`. Two
/// snapshots, because ESI caches the routes for different times and the open list must not wait
/// on history paging.
@Observable
@MainActor
final class OrdersSheet {
    private static let openTTL: TimeInterval = 1200
    private static let historyTTL: TimeInterval = 3600

    let characterID: Int64
    /// Whether the account was granted `esi-markets.read_character_orders.v1`. Fixed for the
    /// sheet's lifetime: a new sign-in creates a new sheet.
    let hasScope: Bool

    private(set) var open: ESISnapshot<ESIOrderList>
    private(set) var history: ESISnapshot<ESIOrderList>

    @ObservationIgnored private let memory: LookupMemory

    init(characterID: Int64, client: Client, hasScope: Bool) {
        self.characterID = characterID
        self.hasScope = hasScope
        let memory = LookupMemory()
        self.memory = memory
        open = ESISnapshot(kind: "orders", characterID: characterID, ttl: Self.openTTL, cache: ESICache()) {
            let payload = try await client.characterOrders(characterID: characterID)
            let orders = payload.map(CharacterOrder.init)
            return ESIOrderList(orders: orders,
                                locations: await LookupMemory.locations(orders.map(\.locationID), memory: memory, client: client))
        }
        history = ESISnapshot(kind: "orders-history", characterID: characterID, ttl: Self.historyTTL, cache: ESICache()) {
            let payload = try await ESIParallel.allPages { page in
                let answer = try await client.characterOrderHistory(characterID: characterID, page: page)
                return (answer.orders, answer.pages)
            }
            var seen: Set<Int64> = []
            let orders = payload.map(CharacterOrder.init).filter { seen.insert($0.id).inserted }
            return ESIOrderList(orders: orders,
                                locations: await LookupMemory.locations(orders.map(\.locationID), memory: memory, client: client))
        }
        memory.seed(locations: (open.value?.locations ?? [:]).merging(history.value?.locations ?? [:]) { new, _ in new })
    }

    /// The account lacks the scope, or ESI answered `403` (a token issued before the scope was
    /// requested).
    var isMissingScope: Bool {
        !hasScope || open.state.isForbidden || history.state.isForbidden
    }

    /// Refreshes the open orders if missing or past their TTL.
    func ensureOpenFresh() async {
        guard hasScope else { return }
        await open.ensureFresh()
    }

    /// Refreshes both lists if missing or past their TTL.
    func ensureFresh() async {
        guard hasScope else { return }
        async let open: Void = open.ensureFresh()
        async let history: Void = history.ensureFresh()
        _ = await (open, history)
    }

    func refresh() async {
        guard hasScope else { return }
        async let open: Void = open.refresh()
        async let history: Void = history.refresh()
        _ = await (open, history)
    }

    /// Stops all disk writes; called by `AccountStore` when it drops the sheet.
    func invalidate() {
        open.invalidate()
        history.invalidate()
    }
}

nonisolated extension CharacterOrder {
    init(_ payload: Components.Schemas.CharactersCharacterIdOrdersGetPayload) {
        self.init(id: payload.orderId,
                  typeID: payload.typeId,
                  regionID: payload.regionId,
                  locationID: payload.locationId,
                  isBuyOrder: payload.isBuyOrder ?? false,
                  isCorporation: payload.isCorporation,
                  price: payload.price,
                  volumeRemain: payload.volumeRemain,
                  volumeTotal: payload.volumeTotal,
                  minVolume: payload.minVolume ?? 1,
                  range: payload.range.rawValue,
                  duration: Int(payload.duration),
                  issued: payload.issued,
                  escrow: payload.escrow,
                  state: .open)
    }

    init(_ payload: Components.Schemas.CharactersCharacterIdOrdersHistoryGetPayload) {
        self.init(id: payload.orderId,
                  typeID: payload.typeId,
                  regionID: payload.regionId,
                  locationID: payload.locationId,
                  isBuyOrder: payload.isBuyOrder ?? false,
                  isCorporation: payload.isCorporation,
                  price: payload.price,
                  volumeRemain: payload.volumeRemain,
                  volumeTotal: payload.volumeTotal,
                  minVolume: payload.minVolume ?? 1,
                  range: payload.range.rawValue,
                  duration: Int(payload.duration),
                  issued: payload.issued,
                  escrow: payload.escrow,
                  state: payload.state == .cancelled ? .cancelled : .expired)
    }
}
