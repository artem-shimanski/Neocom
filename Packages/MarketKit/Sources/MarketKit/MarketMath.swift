import Foundation

/// Which half of the order book.
public enum MarketSide: String, Codable, Sendable, Hashable, CaseIterable {
    /// Sell orders — what a buyer buys from. Best is cheapest.
    case sell
    /// Buy orders — what a seller sells into. Best is dearest.
    case buy
}

/// What filling a quantity from the order book comes to.
public struct MarketFill: Sendable, Hashable {
    /// What was asked for.
    public var requested: Int64
    /// What the book could supply; less than `requested` when it ran out.
    public var filled: Int64
    /// ISK for `filled` units.
    public var total: Double
    /// Orders touched, best first.
    public var ordersUsed: Int
    /// The price of the last (worst) unit taken.
    public var worstPrice: Double?
    /// The systems of the orders touched, each once, in the order first touched.
    public var systemIDs: [Int64]

    public init(requested: Int64, filled: Int64, total: Double, ordersUsed: Int, worstPrice: Double?,
                systemIDs: [Int64] = []) {
        self.requested = requested
        self.filled = filled
        self.total = total
        self.ordersUsed = ordersUsed
        self.worstPrice = worstPrice
        self.systemIDs = systemIDs
    }

    public var isComplete: Bool { filled >= requested }
    public var averagePrice: Double? { filled > 0 ? total / Double(filled) : nil }
}

/// The market arithmetic, as pure functions over plain values.
public enum MarketMath {
    private static let day: TimeInterval = 86_400

    // MARK: - The order book

    /// One side of the book, best first: sells cheapest first, buys dearest first. Equal prices
    /// go oldest first — the order the game itself matches them in.
    public static func sorted(_ orders: [MarketOrder], side: MarketSide) -> [MarketOrder] {
        orders
            .filter { $0.isBuyOrder == (side == .buy) }
            .sorted { lhs, rhs in
                if lhs.price != rhs.price {
                    return side == .sell ? lhs.price < rhs.price : lhs.price > rhs.price
                }
                if lhs.issued != rhs.issued { return lhs.issued < rhs.issued }
                return lhs.id < rhs.id
            }
    }

    /// The cheapest sell order's price.
    public static func bestSell(_ orders: [MarketOrder]) -> Double? {
        orders.lazy.filter { !$0.isBuyOrder }.map(\.price).min()
    }

    /// The dearest buy order's price.
    public static func bestBuy(_ orders: [MarketOrder]) -> Double? {
        orders.lazy.filter(\.isBuyOrder).map(\.price).max()
    }

    /// The gap between best sell and best buy, as a fraction of best sell (`0.05` is 5 %).
    /// Negative when the book is crossed — which happens across stations of one region.
    public static func spread(bestSell: Double?, bestBuy: Double?) -> Double? {
        guard let bestSell, let bestBuy, bestSell > 0 else { return nil }
        return (bestSell - bestBuy) / bestSell
    }

    /// `value` against `reference` as a fraction: `0.1` is 10 % above it.
    public static func relative(_ value: Double?, to reference: Double?) -> Double? {
        guard let value, let reference, reference > 0 else { return nil }
        return value / reference - 1
    }

    /// Takes `quantity` units from `orders`, which must already be best first (see
    /// `sorted(_:side:)`). An order whose `minVolume` exceeds what is still needed is skipped:
    /// the game would not let that trade happen.
    public static func fill(_ quantity: Int64, from orders: [MarketOrder]) -> MarketFill {
        var remaining = max(quantity, 0)
        var filled: Int64 = 0
        var total: Double = 0
        var used = 0
        var worst: Double?
        var systems: [Int64] = []
        for order in orders where remaining > 0 {
            let take = min(remaining, order.volumeRemain)
            guard take > 0, take >= order.minVolume else { continue }
            remaining -= take
            filled += take
            total += Double(take) * order.price
            used += 1
            worst = order.price
            if !systems.contains(order.systemID) { systems.append(order.systemID) }
        }
        return MarketFill(requested: max(quantity, 0), filled: filled, total: total, ordersUsed: used, worstPrice: worst,
                          systemIDs: systems)
    }

    /// The order fewest jumps away, cheapest among equals (for sells; dearest for buys).
    /// Orders whose system has no known distance are left out; `nil` when none has one.
    public static func nearest(_ orders: [MarketOrder], jumps: [Int64: Int]) -> (order: MarketOrder, jumps: Int)? {
        var best: (order: MarketOrder, jumps: Int)?
        for order in orders {
            guard let distance = jumps[order.systemID] else { continue }
            if let current = best {
                if distance > current.jumps { continue }
                if distance == current.jumps {
                    let better = order.isBuyOrder ? order.price > current.order.price : order.price < current.order.price
                    if !better { continue }
                }
            }
            best = (order, distance)
        }
        return best
    }

    // MARK: - History

    /// The days of the `days`-long window that ends at the start of `asOf`'s UTC day —
    /// today has no history entry yet — oldest first. Without `asOf` the window ends the day
    /// after the latest entry.
    public static func trailing(_ history: [MarketHistoryDay], days: Int, asOf: Date? = nil) -> [MarketHistoryDay] {
        guard let end = windowEnd(history, asOf: asOf) else { return [] }
        let start = end.addingTimeInterval(-Double(days) * day)
        return history
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }
    }

    /// The change of the daily average across the window: last day's against first day's,
    /// as a fraction. `nil` with fewer than two days in it.
    public static func change(_ history: [MarketHistoryDay], days: Int = 30, asOf: Date? = nil) -> Double? {
        let window = trailing(history, days: days, asOf: asOf)
        guard window.count >= 2, let first = window.first, let last = window.last else { return nil }
        return relative(last.average, to: first.average)
    }

    /// Units traded per day over the window. Days without trades — which history leaves out —
    /// count as zero; an item younger than the window is averaged over its own lifetime.
    public static func averageDailyVolume(_ history: [MarketHistoryDay], days: Int = 30, asOf: Date? = nil) -> Double? {
        guard let end = windowEnd(history, asOf: asOf), let firstEver = history.map(\.date).min() else { return nil }
        let window = trailing(history, days: days, asOf: asOf)
        let lifetime = Int((end.timeIntervalSince(firstEver) / day).rounded())
        let span = min(days, max(lifetime, 1))
        let volume = window.reduce(Int64(0)) { $0 + $1.volume }
        return Double(volume) / Double(span)
    }

    /// Folds days into buckets of `bucketDays` consecutive calendar days, aligned to the last
    /// day — a year of history drawn as weekly bars. The bucket is dated by its first day, its
    /// average is weighted by volume, its band is the widest of its days.
    public static func aggregate(_ history: [MarketHistoryDay], bucketDays: Int) -> [MarketHistoryDay] {
        let days = history.sorted { $0.date < $1.date }
        guard bucketDays > 1, let last = days.last?.date else { return days }
        var buckets: [Int: [MarketHistoryDay]] = [:]
        for entry in days {
            let back = Int((last.timeIntervalSince(entry.date) / day).rounded())
            buckets[back / bucketDays, default: []].append(entry)
        }
        return buckets.keys.sorted(by: >).compactMap { key -> MarketHistoryDay? in
            guard let entries = buckets[key], let first = entries.first else { return nil }
            let volume = entries.reduce(Int64(0)) { $0 + $1.volume }
            let weighted = entries.reduce(0.0) { $0 + $1.average * Double($1.volume) }
            let average = volume > 0 ? weighted / Double(volume) : entries.map(\.average).reduce(0, +) / Double(entries.count)
            return MarketHistoryDay(date: first.date,
                                    average: average,
                                    lowest: entries.map(\.lowest).min() ?? first.lowest,
                                    highest: entries.map(\.highest).max() ?? first.highest,
                                    volume: volume,
                                    orderCount: entries.reduce(Int64(0)) { $0 + $1.orderCount })
        }
    }

    private static func windowEnd(_ history: [MarketHistoryDay], asOf: Date?) -> Date? {
        if let asOf { return Calendar.utc.startOfDay(for: asOf) }
        return history.map(\.date).max()?.addingTimeInterval(day)
    }
}

/// The numbers the price card and the top of the market screen show, from one region's order
/// book and history.
public struct MarketSummary: Sendable, Hashable {
    public var bestSell: Double?
    public var bestBuy: Double?
    /// See `MarketMath.spread(bestSell:bestBuy:)`.
    public var spread: Double?
    public var averageDailyVolume: Double?
    /// CCP's universe-wide average (`/markets/prices`).
    public var ccpAverage: Double?
    /// Best sell against the CCP average, as a fraction.
    public var versusCCP: Double?
    /// The change of the daily average over the window, as a fraction.
    public var change: Double?
    /// The daily averages of the window, oldest first.
    public var sparkline: [Double]
    public var sellOrderCount: Int
    public var buyOrderCount: Int

    public static let windowDays = 30

    /// `orders` and `history` may be `nil` while they are loading; what depends on them is
    /// then `nil` too.
    public init(orders: [MarketOrder]?, history: [MarketHistoryDay]?, ccpAverage: Double?, asOf: Date? = nil) {
        let orders = orders ?? []
        let history = history ?? []
        bestSell = MarketMath.bestSell(orders)
        bestBuy = MarketMath.bestBuy(orders)
        spread = MarketMath.spread(bestSell: bestSell, bestBuy: bestBuy)
        self.ccpAverage = ccpAverage
        versusCCP = MarketMath.relative(bestSell, to: ccpAverage)
        averageDailyVolume = MarketMath.averageDailyVolume(history, days: Self.windowDays, asOf: asOf)
        change = MarketMath.change(history, days: Self.windowDays, asOf: asOf)
        sparkline = MarketMath.trailing(history, days: Self.windowDays, asOf: asOf).map(\.average)
        sellOrderCount = orders.count { !$0.isBuyOrder }
        buyOrderCount = orders.count { $0.isBuyOrder }
    }
}
