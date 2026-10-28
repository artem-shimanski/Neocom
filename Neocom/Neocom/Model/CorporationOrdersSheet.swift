import AssetsKit
import BusinessKit
import ESIKit
import Foundation
import Observation

/// A corporation's market orders, as seen by one of its characters: the open ones and 90 days
/// of history.
///
/// The only owner of `/corporations/{id}/orders` and `/corporations/{id}/orders/history`. Cached
/// per viewing character, with the corporation id in the kind. Read by the background check
/// for the corporation's notifications; nothing reaches widgets.
@Observable
@MainActor
final class CorporationOrdersSheet {
    private static let openTTL: TimeInterval = 1200
    private static let historyTTL: TimeInterval = 3600

    /// The viewer.
    let characterID: Int64
    let boundCorporationID: Int64
    /// Whether the account was granted `esi-markets.read_corporation_orders.v1`.
    let hasScope: Bool

    private(set) var open: ESISnapshot<ESIOrderList>
    private(set) var history: ESISnapshot<ESIOrderList>

    var corporationID: Int64? { boundCorporationID }

    var access: BusinessAccess {
        .corporation(hasScope: hasScope, isForbidden: open.state.isForbidden || history.state.isForbidden)
    }

    @ObservationIgnored private let memory: LookupMemory

    init(characterID: Int64, corporationID: Int64, client: Client, hasScope: Bool) {
        self.characterID = characterID
        self.boundCorporationID = corporationID
        self.hasScope = hasScope
        let memory = LookupMemory()
        self.memory = memory
        open = ESISnapshot(kind: "corp-\(corporationID)-orders", characterID: characterID, ttl: Self.openTTL, cache: ESICache()) {
            let payload = try await ESIParallel.allPages { page in
                let answer = try await client.corporationOrders(corporationID: corporationID, page: page)
                return (answer.orders, answer.pages)
            }
            var seen: Set<Int64> = []
            let orders = payload.map(CharacterOrder.init).filter { seen.insert($0.id).inserted }
            return await Self.list(orders, memory: memory, client: client)
        }
        history = ESISnapshot(kind: "corp-\(corporationID)-orders-history", characterID: characterID, ttl: Self.historyTTL, cache: ESICache()) {
            let payload = try await ESIParallel.allPages { page in
                let answer = try await client.corporationOrderHistory(corporationID: corporationID, page: page)
                return (answer.orders, answer.pages)
            }
            var seen: Set<Int64> = []
            let orders = payload.map(CharacterOrder.init).filter { seen.insert($0.id).inserted }
            return await Self.list(orders, memory: memory, client: client)
        }
        memory.seed(locations: (open.value?.locations ?? [:]).merging(history.value?.locations ?? [:]) { new, _ in new },
                    names: (open.value?.names ?? [:]).merging(history.value?.names ?? [:]) { new, _ in new })
    }

    nonisolated private static func list(_ orders: [CharacterOrder], memory: LookupMemory, client: Client) async -> ESIOrderList {
        async let locations = LookupMemory.locations(orders.map(\.locationID), memory: memory, client: client)
        async let names = LookupMemory.names(orders.compactMap(\.issuedBy), memory: memory, client: client)
        return ESIOrderList(orders: orders, locations: await locations, names: await names)
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

extension CorporationOrdersSheet: OrdersSource, CorporationBound {}

nonisolated extension CharacterOrder {
    init(_ payload: Components.Schemas.CorporationsCorporationIdOrdersGetPayload) {
        self.init(id: payload.orderId,
                  typeID: payload.typeId,
                  regionID: payload.regionId,
                  locationID: payload.locationId,
                  isBuyOrder: payload.isBuyOrder ?? false,
                  isCorporation: true,
                  price: payload.price,
                  volumeRemain: payload.volumeRemain,
                  volumeTotal: payload.volumeTotal,
                  minVolume: payload.minVolume ?? 1,
                  range: payload.range.rawValue,
                  duration: Int(payload.duration),
                  issued: payload.issued,
                  escrow: payload.escrow,
                  state: .open,
                  walletDivision: Int(clamping: payload.walletDivision),
                  issuedBy: payload.issuedBy)
    }

    init(_ payload: Components.Schemas.CorporationsCorporationIdOrdersHistoryGetPayload) {
        self.init(id: payload.orderId,
                  typeID: payload.typeId,
                  regionID: payload.regionId,
                  locationID: payload.locationId,
                  isBuyOrder: payload.isBuyOrder ?? false,
                  isCorporation: true,
                  price: payload.price,
                  volumeRemain: payload.volumeRemain,
                  volumeTotal: payload.volumeTotal,
                  minVolume: payload.minVolume ?? 1,
                  range: payload.range.rawValue,
                  duration: Int(payload.duration),
                  issued: payload.issued,
                  escrow: payload.escrow,
                  state: payload.state == .cancelled ? .cancelled : .expired,
                  walletDivision: Int(clamping: payload.walletDivision),
                  issuedBy: payload.issuedBy)
    }
}
