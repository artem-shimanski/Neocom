import ESIKit
import Foundation
import MarketKit
import Observation

/// CCP's average prices from `/markets/prices`, as stored in `ESICache`.
nonisolated struct MarketPrices: Codable, Sendable, Hashable {
    /// `average_price` by type id; types without one are omitted.
    var average: [Int64: Double]
}

/// One type in one region: the key of an order book and a price history.
nonisolated struct MarketKey: Sendable, Hashable {
    var regionID: Int64
    var typeID: Int64
}

/// Public market data, app-wide.
///
/// The only owner of `/markets/prices`, `/markets/{region_id}/orders`,
/// `/markets/{region_id}/history`, `/route/{origin}/{destination}` and the order book's station
/// names. Cached on disk under `ESICache.Owner.universe`; the last `capacity` snapshots per
/// region and type are also kept in memory.
@Observable
@MainActor
final class MarketSheet {
    /// ESI's cache time for orders.
    static let ordersTTL: TimeInterval = 300
    /// ESI's cache time for `/markets/prices`.
    static let pricesTTL: TimeInterval = 3600
    /// Order books and histories kept in memory.
    static let capacity = 32
    /// Order and history files not written for this long are deleted at launch.
    static let fileLifetime: TimeInterval = 7 * 86_400

    let regions: MarketRegionPreference
    private(set) var prices: ESISnapshot<MarketPrices>

    /// Resolved NPC station names. Player structures are not included: public routes do not
    /// name them.
    private(set) var stationNames: [Int64: String]
    /// Known gate jump counts between systems.
    private(set) var jumpCounts: [JumpKey: Int] = [:]
    /// Pairs of systems with no gate route between them.
    private(set) var unreachable: Set<JumpKey> = []

    nonisolated struct JumpKey: Sendable, Hashable {
        var origin: Int64
        var destination: Int64
    }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private let cache: ESICache
    @ObservationIgnored private var orderBooks: [MarketKey: ESISnapshot<[MarketOrder]>] = [:]
    @ObservationIgnored private var histories: [MarketKey: ESISnapshot<[MarketHistoryDay]>] = [:]
    /// Every snapshot handed out, held weakly, so a snapshot evicted from the caches above but
    /// still on screen is returned again instead of a duplicate with its own fetch.
    @ObservationIgnored private var liveOrderBooks: [MarketKey: WeakSnapshot<[MarketOrder]>] = [:]
    @ObservationIgnored private var liveHistories: [MarketKey: WeakSnapshot<[MarketHistoryDay]>] = [:]
    /// Keys by last use, most recent last.
    @ObservationIgnored private var recency: [MarketKey] = []
    /// Station ids already requested, each once per launch.
    @ObservationIgnored private var askedStations: Set<Int64> = []
    @ObservationIgnored private var askedJumps: Set<JumpKey> = []
    /// When the cached station names were first gathered; `stationsLifetime` runs from here.
    @ObservationIgnored private var stationsGatheredAt: Date?

    private static let stationsKind = "market-stations"
    /// Stations are occasionally renamed.
    private static let stationsLifetime: TimeInterval = 30 * 86_400
    nonisolated private static let width = 5

    // `cache` and `regions` default to `nil` so the defaults are created on the main actor.
    init(client: Client = ESIService.publicClient, cache: ESICache? = nil, regions: MarketRegionPreference? = nil) {
        let cache = cache ?? ESICache()
        self.client = client
        self.cache = cache
        self.regions = regions ?? MarketRegionPreference()
        prices = Self.makePrices(client: client, cache: cache)

        let stations = cache.load([Int64: String].self, kind: Self.stationsKind, owner: .universe)
        if let stations, Date.now.timeIntervalSince(stations.fetchedAt) < Self.stationsLifetime {
            stationNames = stations.value
            stationsGatheredAt = stations.fetchedAt
        } else {
            stationNames = [:]
        }

        let cutoff = Date.now.addingTimeInterval(-Self.fileLifetime)
        cache.removeFiles(of: .universe, prefix: "market-orders-", writtenBefore: cutoff)
        cache.removeFiles(of: .universe, prefix: "market-history-", writtenBefore: cutoff)
    }

    private static func makePrices(client: Client, cache: ESICache) -> ESISnapshot<MarketPrices> {
        ESISnapshot(kind: "market-prices", owner: .universe, ttl: Self.pricesTTL, cache: cache) {
            let rows = try await client.marketPrices()
            var average: [Int64: Double] = [:]
            for row in rows {
                if let price = row.averagePrice { average[row.typeId] = price }
            }
            return MarketPrices(average: average)
        }
    }

    /// Invalidates and drops every snapshot and resolved name; called by `CachedData.clear`.
    /// The region preference is kept.
    func dropCachedData() {
        prices.invalidate()
        prices = Self.makePrices(client: client, cache: cache)
        for snapshot in orderBooks.values { snapshot.invalidate() }
        for snapshot in histories.values { snapshot.invalidate() }
        for weak in liveOrderBooks.values { weak.snapshot?.invalidate() }
        for weak in liveHistories.values { weak.snapshot?.invalidate() }
        orderBooks = [:]
        histories = [:]
        liveOrderBooks = [:]
        liveHistories = [:]
        recency = []
        stationNames = [:]
        askedStations = []
        stationsGatheredAt = nil
        jumpCounts = [:]
        unreachable = []
        askedJumps = []
    }

    // MARK: - Prices

    func ccpAverage(of typeID: Int64) -> Double? {
        prices.value?.average[typeID]
    }

    func ensurePricesFresh() async {
        await prices.ensureFresh()
    }

    // MARK: - Orders and history

    /// All buy and sell orders of a type in a region, unsorted. The same snapshot for the same
    /// key while it is alive.
    func orders(typeID: Int64, regionID: Int64) -> ESISnapshot<[MarketOrder]> {
        let key = MarketKey(regionID: regionID, typeID: typeID)
        touch(key)
        if let snapshot = orderBooks[key] { return snapshot }
        if let snapshot = liveOrderBooks[key]?.snapshot {
            orderBooks[key] = snapshot
            return snapshot
        }
        let client = client
        let snapshot = ESISnapshot<[MarketOrder]>(kind: "market-orders-\(regionID)-\(typeID)",
                                                  owner: .universe, ttl: Self.ordersTTL, cache: cache) {
            try await Self.fetchOrders(regionID: regionID, typeID: typeID, client: client)
        }
        orderBooks[key] = snapshot
        liveOrderBooks[key] = WeakSnapshot(snapshot: snapshot)
        return snapshot
    }

    /// The daily history of a type in a region, oldest first. Fresh until the route's next daily
    /// renewal.
    func history(typeID: Int64, regionID: Int64) -> ESISnapshot<[MarketHistoryDay]> {
        let key = MarketKey(regionID: regionID, typeID: typeID)
        touch(key)
        if let snapshot = histories[key] { return snapshot }
        if let snapshot = liveHistories[key]?.snapshot {
            histories[key] = snapshot
            return snapshot
        }
        let client = client
        let snapshot = ESISnapshot<[MarketHistoryDay]>(kind: "market-history-\(regionID)-\(typeID)",
                                                       owner: .universe, cache: cache,
                                                       freshUntil: Self.nextHistoryRenewal(after:)) {
            try await client.marketHistory(regionID: regionID, typeID: typeID)
                .compactMap(MarketHistoryDay.init)
                .sorted { $0.date < $1.date }
        }
        histories[key] = snapshot
        liveHistories[key] = WeakSnapshot(snapshot: snapshot)
        return snapshot
    }

    /// The next 11:10 UTC after `date`: ESI publishes a new day of history at about 11:05.
    nonisolated static func nextHistoryRenewal(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let today = calendar.date(bySettingHour: 11, minute: 10, second: 0, of: date) else {
            return date.addingTimeInterval(86_400)
        }
        return today > date ? today : today.addingTimeInterval(86_400)
    }

    private func touch(_ key: MarketKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
        guard recency.count > Self.capacity else { return }
        while recency.count > Self.capacity {
            let dropped = recency.removeFirst()
            orderBooks[dropped] = nil
            histories[dropped] = nil
        }
        liveOrderBooks = liveOrderBooks.filter { $0.value.snapshot != nil }
        liveHistories = liveHistories.filter { $0.value.snapshot != nil }
    }

    private struct WeakSnapshot<Value: Codable & Sendable> {
        weak var snapshot: ESISnapshot<Value>?
    }

    /// All pages of the book, deduplicated by order id. A failed page fails the whole fetch,
    /// since a partial book would show a wrong best price.
    nonisolated private static func fetchOrders(regionID: Int64, typeID: Int64, client: Client) async throws -> [MarketOrder] {
        let first = try await client.marketOrders(regionID: regionID, typeID: typeID, page: 1)
        var payloads = first.orders
        if first.pages > 1 {
            let rest = try await boundedMap(Array(2...first.pages)) { page in
                try await client.marketOrders(regionID: regionID, typeID: typeID, page: page).orders
            }
            for page in rest { payloads += page }
        }
        var seen: Set<Int64> = []
        return payloads
            .filter { seen.insert($0.orderId).inserted }
            .map(MarketOrder.init)
    }

    // MARK: - Station names

    /// Resolves the unnamed NPC stations among `locationIDs` and caches them on disk. Best
    /// effort, each id requested once per launch.
    func resolveStationNames(_ locationIDs: some Sequence<Int64>) async {
        let ask = Set(locationIDs)
            .filter { MarketOrder.stationIDs.contains($0) && stationNames[$0] == nil && !askedStations.contains($0) }
            .sorted()
        guard !ask.isEmpty else { return }
        askedStations.formUnion(ask)

        let client = client
        let chunks = stride(from: 0, to: ask.count, by: 1000).map { Array(ask[$0..<min($0 + 1000, ask.count)]) }
        let answers = (try? await Self.boundedMap(chunks) { chunk in
            (try? await client.stationNames(stationIDs: chunk)) ?? [:]
        }) ?? []
        var found: [Int64: String] = [:]
        for answer in answers { found.merge(answer) { _, new in new } }
        guard !found.isEmpty else {
            // Likely offline; allow a later retry.
            askedStations.subtract(ask)
            return
        }
        stationNames.merge(found) { _, new in new }
        let gatheredAt = stationsGatheredAt ?? .now
        stationsGatheredAt = gatheredAt
        cache.save(.init(value: stationNames, fetchedAt: gatheredAt), kind: Self.stationsKind, owner: .universe)
    }

    // MARK: - Jumps

    /// Gate jumps from `origin` to `destination`: `0` within one system, `nil` while unknown or
    /// when there is no route (see `isUnreachable(from:to:)`).
    func jumps(from origin: Int64, to destination: Int64) -> Int? {
        if origin == destination { return 0 }
        return jumpCounts[JumpKey(origin: origin, destination: destination)]
    }

    func isUnreachable(from origin: Int64, to destination: Int64) -> Bool {
        unreachable.contains(JumpKey(origin: origin, destination: destination))
    }

    /// Requests the unknown routes from `origin` to `destinations`, one request per system.
    /// Failures other than "no route" are retried on the next call.
    func resolveJumps(from origin: Int64, to destinations: some Sequence<Int64>) async {
        let keys = Set(destinations)
            .filter { $0 != origin }
            .map { JumpKey(origin: origin, destination: $0) }
            .filter { jumpCounts[$0] == nil && !unreachable.contains($0) && !askedJumps.contains($0) }
        guard !keys.isEmpty else { return }
        askedJumps.formUnion(keys)

        let client = client
        let answers = (try? await Self.boundedMap(keys) { key -> (JumpKey, RouteAnswer) in
            do {
                let route = try await client.route(from: key.origin, to: key.destination)
                return (key, .jumps(max(route.count - 1, 0)))
            } catch let ESIError.http(status, _) where status == 404 {
                return (key, .none)
            } catch {
                return (key, .failed)
            }
        }) ?? []

        askedJumps.subtract(keys)
        for (key, answer) in answers {
            switch answer {
            case let .jumps(count): jumpCounts[key] = count
            case .none: unreachable.insert(key)
            case .failed: break
            }
        }
    }

    nonisolated private enum RouteAnswer: Sendable {
        case jumps(Int)
        /// ESI reports no route.
        case none
        case failed
    }

    // MARK: -

    /// Maps `body` over `items` with at most `width` running at once; results are in completion
    /// order.
    nonisolated private static func boundedMap<Item: Sendable, Answer: Sendable>(
        _ items: [Item],
        _ body: @escaping @Sendable (Item) async throws -> Answer
    ) async throws -> [Answer] {
        try await withThrowingTaskGroup(of: Answer.self) { group in
            var next = 0
            for _ in 0..<min(width, items.count) {
                let item = items[next]
                group.addTask { try await body(item) }
                next += 1
            }
            var answers: [Answer] = []
            answers.reserveCapacity(items.count)
            while let answer = try await group.next() {
                answers.append(answer)
                if next < items.count {
                    let item = items[next]
                    group.addTask { try await body(item) }
                    next += 1
                }
            }
            return answers
        }
    }
}

nonisolated extension MarketOrder {
    init(_ payload: Components.Schemas.MarketsRegionIdOrdersGetPayload) {
        self.init(id: payload.orderId,
                  isBuyOrder: payload.isBuyOrder,
                  price: payload.price,
                  volumeRemain: payload.volumeRemain,
                  volumeTotal: payload.volumeTotal,
                  minVolume: payload.minVolume,
                  locationID: payload.locationId,
                  systemID: payload.systemId,
                  range: payload.range.rawValue,
                  issued: payload.issued)
    }
}

nonisolated extension MarketHistoryDay {
    /// `nil` for a day whose date does not parse.
    init?(_ payload: Components.Schemas.MarketsRegionIdHistoryGetPayload) {
        guard let date = MarketHistoryDay.date(fromESI: payload.date) else { return nil }
        self.init(date: date, average: payload.average, lowest: payload.lowest, highest: payload.highest,
                  volume: payload.volume, orderCount: payload.orderCount)
    }
}
