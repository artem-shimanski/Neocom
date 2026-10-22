import Foundation
import LiteRow
import MarketKit
import Observation
import SDEKit

/// One order as the order book draws it: the order, and where it is in words.
struct MarketOrderRow: Sendable, Hashable, Identifiable {
    var order: MarketOrder
    /// The station's name; `nil` for a player structure (`isStructure`) or a station not
    /// named yet.
    var stationName: String?
    var systemName: String?
    /// Raw security status of the system, as the static data has it.
    var securityStatus: Double?
    /// Gate jumps from the pilot's system: `nil` without a pilot, while unknown, or when there
    /// is no route.
    var jumps: Int?

    var id: Int64 { order.id }
    /// The order sits in a player-owned structure, which public data does not name.
    var isStructure: Bool { !order.isInStation }
}

/// What the price card and the market screen read for one type in one region: the summary, both
/// sides of the order book with locations resolved, the history and the quantity calculator.
/// Built per region; it never fetches on its own, the snapshots belong to `MarketSheet`.
@Observable
@MainActor
final class MarketTypeModel {
    let typeID: Int64
    let regionID: Int64
    let orders: ESISnapshot<[MarketOrder]>
    let history: ESISnapshot<[MarketHistoryDay]>

    /// Systems of the order book, named, from the static data. Filled by `load()`.
    private(set) var systems: [Int64: MarketSystemRow] = [:]

    /// How many rows of each side `load()` resolves jumps for.
    static let visibleRows = 10
    /// How many distinct sell systems, best first, are asked for jumps to find the nearest sell
    /// order; one route request each.
    static let nearestCandidates = 25

    @ObservationIgnored private let sheet: MarketSheet
    @ObservationIgnored private let characterSheet: CharacterSheet?
    @ObservationIgnored private var cachedBook: (revision: Int, sell: [MarketOrder], buy: [MarketOrder])?
    @ObservationIgnored private var cachedSummary: (key: [Int], summary: MarketSummary)?

    /// `regionID` defaults to the region preference. `characterSheet` is the pilot's, for the
    /// jumps; without one there are none.
    init(sheet: MarketSheet, typeID: Int64, regionID: Int64? = nil, characterSheet: CharacterSheet? = nil) {
        let regionID = regionID ?? sheet.regions.regionID
        self.sheet = sheet
        self.typeID = typeID
        self.regionID = regionID
        self.characterSheet = characterSheet
        orders = sheet.orders(typeID: typeID, regionID: regionID)
        history = sheet.history(typeID: typeID, regionID: regionID)
    }

    // MARK: - Reading

    /// The pilot's solar system, if there is a pilot and their profile has been fetched.
    var pilotSystemID: Int64? { characterSheet?.currentSolarSystemID }

    var ccpAverage: Double? { sheet.ccpAverage(of: typeID) }

    /// Best prices, spread, volume, the CCP comparison, the 30-day change and the sparkline.
    /// Fields whose data has not arrived yet are `nil`.
    var summary: MarketSummary {
        let key = [orders.revision, history.revision, sheet.prices.revision]
        if let cachedSummary, cachedSummary.key == key { return cachedSummary.summary }
        let summary = MarketSummary(orders: orders.value, history: history.value, ccpAverage: ccpAverage, asOf: .now)
        cachedSummary = (key, summary)
        return summary
    }

    /// One side of the book, best first.
    func book(_ side: MarketSide) -> [MarketOrder] {
        if cachedBook?.revision != orders.revision {
            let all = orders.value ?? []
            cachedBook = (orders.revision, MarketMath.sorted(all, side: .sell), MarketMath.sorted(all, side: .buy))
        }
        return side == .sell ? cachedBook?.sell ?? [] : cachedBook?.buy ?? []
    }

    /// One side of the book as rows, best first; `limit` for the top of it.
    func rows(_ side: MarketSide, limit: Int? = nil) -> [MarketOrderRow] {
        let orders = book(side)
        return (limit.map { Array(orders.prefix($0)) } ?? orders).map(row)
    }

    /// The sell order fewest jumps from the pilot (cheapest among equals), among those whose
    /// distance is known. `nil` without a pilot.
    var nearestSell: MarketOrderRow? {
        guard let origin = pilotSystemID else { return nil }
        let sells = book(.sell)
        var jumps: [Int64: Int] = [:]
        for system in Set(sells.map(\.systemID)) {
            if let count = sheet.jumps(from: origin, to: system) { jumps[system] = count }
        }
        return MarketMath.nearest(sells, jumps: jumps).map { row($0.order) }
    }

    /// What `quantity` units cost bought from the best sell orders (`.sell`), or fetch sold
    /// into the best buy orders (`.buy`).
    func fill(_ quantity: Int64, side: MarketSide = .sell) -> MarketFill {
        MarketMath.fill(quantity, from: book(side))
    }

    /// The last `days` days of history, oldest first — 30, 90 or 365 for the chart. Fold a
    /// year into weeks with `MarketMath.aggregate(_:bucketDays:)` if it is too dense.
    func history(lastDays days: Int) -> [MarketHistoryDay] {
        MarketMath.trailing(history.value ?? [], days: days, asOf: .now)
    }

    private func row(_ order: MarketOrder) -> MarketOrderRow {
        let system = systems[order.systemID]
        return MarketOrderRow(order: order,
                              stationName: order.isInStation ? sheet.stationNames[order.locationID] : nil,
                              systemName: system?.name,
                              securityStatus: system?.securityStatus,
                              jumps: pilotSystemID.flatMap { sheet.jumps(from: $0, to: order.systemID) })
    }

    // MARK: - Loading

    /// For the price card: orders, history and CCP prices, each only if stale.
    func loadPrices() async {
        let orders = orders, history = history, sheet = sheet
        async let o: Void = orders.ensureFresh()
        async let h: Void = history.ensureFresh()
        async let p: Void = sheet.ensurePricesFresh()
        _ = await (o, h, p)
    }

    /// For the market screen: `loadPrices()`, then the book's systems, station names and, with a
    /// pilot, the jumps to the visible rows and the nearest sell candidates. The cached book is
    /// resolved while the network is asked.
    func load(database: SDEDatabase?) async {
        await resolveLocations(database: database)
        let before = orders.revision
        async let prices: Void = loadPrices()
        if let characterSheet { await characterSheet.ensureLocationKnown() }
        await prices
        if orders.revision != before || pilotSystemID != nil {
            await resolveLocations(database: database)
        }
    }

    /// Pull-to-refresh: the book and the history regardless of their freshness.
    func refresh(database: SDEDatabase?) async {
        let orders = orders, history = history
        async let o: Void = orders.refresh()
        async let h: Void = history.refresh()
        _ = await (o, h)
        await resolveLocations(database: database)
    }

    /// Resolves jumps for more rows than the visible ones.
    func resolveJumps(for rows: [MarketOrderRow]) async {
        guard let origin = pilotSystemID else { return }
        await sheet.resolveJumps(from: origin, to: rows.map(\.order.systemID))
    }

    private func resolveLocations(database: SDEDatabase?) async {
        let all = orders.value ?? []
        guard !all.isEmpty else { return }

        if let database {
            let missing = Set(all.map(\.systemID)).filter { systems[$0] == nil }
                .map { SolarSystemID(rawValue: UInt32(clamping: $0)) }
            if !missing.isEmpty {
                let queries = stride(from: 0, to: missing.count, by: 500).map {
                    MarketBrowser.systems(Array(missing[$0..<min($0 + 500, missing.count)]))
                }
                if let rows = try? await database.database.read({ reader in
                    try queries.flatMap { try reader.fetchAll($0) }
                }) {
                    for row in rows { systems[Int64(row.id.rawValue)] = row }
                }
            }
        }

        let sheet = sheet
        async let names: Void = sheet.resolveStationNames(all.map(\.locationID))
        async let jumps: Void = resolveVisibleJumps()
        _ = await (names, jumps)
    }

    private func resolveVisibleJumps() async {
        guard let origin = pilotSystemID else { return }
        let sells = book(.sell), buys = book(.buy)
        var destinations = Set(sells.prefix(Self.visibleRows).map(\.systemID))
        destinations.formUnion(buys.prefix(Self.visibleRows).map(\.systemID))
        var candidates: [Int64] = []
        for order in sells where !candidates.contains(order.systemID) {
            candidates.append(order.systemID)
            if candidates.count == Self.nearestCandidates { break }
        }
        destinations.formUnion(candidates)
        await sheet.resolveJumps(from: origin, to: destinations)
    }
}
