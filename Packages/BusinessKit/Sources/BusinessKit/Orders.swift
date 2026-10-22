import Foundation

// A character's own market orders: `/characters/{id}/orders` (open ones) and
// `/characters/{id}/orders/history` (expired and cancelled, 90 days). Plain data,
// independent of the ESI types.

/// One of the character's market orders, open or from history.
public struct CharacterOrder: Codable, Sendable, Hashable, Identifiable {
    /// Where ESI says the order stands. Open orders come from `/orders`, the other two from
    /// `/orders/history`.
    public enum State: String, Codable, Sendable, Hashable {
        case open
        case expired
        case cancelled
    }

    /// The order id.
    public var id: Int64
    public var typeID: Int64
    public var regionID: Int64
    /// A station or a structure.
    public var locationID: Int64
    public var isBuyOrder: Bool
    /// Placed on behalf of the character's corporation.
    public var isCorporation: Bool
    /// ISK per unit.
    public var price: Double
    public var volumeRemain: Int64
    public var volumeTotal: Int64
    /// Buy orders only; 1 otherwise.
    public var minVolume: Int64
    /// `"station"`, `"solarsystem"`, `"region"` or a number of jumps. Raw, so a value CCP adds
    /// later survives a cached file.
    public var range: String
    /// Days.
    public var duration: Int
    public var issued: Date
    /// ISK held for a buy order. ESI leaves it out for sell orders.
    public var escrow: Double?
    public var state: State

    public init(id: Int64, typeID: Int64, regionID: Int64, locationID: Int64, isBuyOrder: Bool,
                isCorporation: Bool = false, price: Double, volumeRemain: Int64, volumeTotal: Int64,
                minVolume: Int64 = 1, range: String = "region", duration: Int, issued: Date,
                escrow: Double? = nil, state: State = .open) {
        self.id = id
        self.typeID = typeID
        self.regionID = regionID
        self.locationID = locationID
        self.isBuyOrder = isBuyOrder
        self.isCorporation = isCorporation
        self.price = price
        self.volumeRemain = volumeRemain
        self.volumeTotal = volumeTotal
        self.minVolume = minVolume
        self.range = range
        self.duration = duration
        self.issued = issued
        self.escrow = escrow
        self.state = state
    }
}

/// How an order ended — or that it has not. `filled` is not an ESI state: history only says
/// `expired`, and an expired order with nothing left traded in full.
public enum OrderOutcome: String, Codable, Sendable, Hashable {
    case open
    case filled
    case expired
    case cancelled
}

extension CharacterOrder {
    /// Below this much time left an open order is flagged `EXPIRES SOON`.
    public static let expiringSoonInterval: TimeInterval = 86_400

    /// When the order expires (for history: when it would have — ESI does not say when it
    /// closed).
    public var expires: Date { issued.addingTimeInterval(TimeInterval(duration) * 86_400) }

    /// Time until `expires`, never negative.
    public func timeLeft(at now: Date) -> TimeInterval { max(0, expires.timeIntervalSince(now)) }

    /// An open order with less than a day left.
    public func isExpiringSoon(at now: Date) -> Bool {
        state == .open && expires.timeIntervalSince(now) < Self.expiringSoonInterval
    }

    public var outcome: OrderOutcome {
        switch state {
        case .open: .open
        case .cancelled: .cancelled
        case .expired: volumeRemain == 0 ? .filled : .expired
        }
    }

    /// Units already bought or sold.
    public var volumeTraded: Int64 { max(0, volumeTotal - volumeRemain) }

    /// What is left of the order, 0…1 — the bar's fill.
    public var remainingFraction: Double {
        volumeTotal > 0 ? min(1, max(0, Double(volumeRemain) / Double(volumeTotal))) : 0
    }

    /// `price × volumeRemain`: what a sell order still earns, what a buy order still spends.
    public var remainingValue: Double { price * Double(volumeRemain) }
}

/// The figures of the orders screen's summary strip and of its tile.
public struct OrdersSummary: Sendable, Hashable {
    public var openCount: Int
    public var sellCount: Int
    public var buyCount: Int
    /// ISK the open sell orders still earn.
    public var sellTotal: Double
    /// ISK the open buy orders still spend.
    public var buyTotal: Double
    /// ISK held in escrow by the open buy orders.
    public var escrow: Double
    /// Open orders with less than a day left.
    public var expiringSoonCount: Int

    /// Over the open orders in `orders`; history entries are ignored.
    public init(_ orders: [CharacterOrder], now: Date) {
        let open = orders.filter { $0.state == .open }
        let sells = open.filter { !$0.isBuyOrder }
        let buys = open.filter(\.isBuyOrder)
        openCount = open.count
        sellCount = sells.count
        buyCount = buys.count
        sellTotal = sells.reduce(0) { $0 + $1.remainingValue }
        buyTotal = buys.reduce(0) { $0 + $1.remainingValue }
        escrow = buys.reduce(0) { $0 + ($1.escrow ?? 0) }
        expiringSoonCount = open.filter { $0.isExpiringSoon(at: now) }.count
    }
}

// MARK: - Place in the order book

/// One order of a region's book, with the fields the position needs.
public struct BookOrder: Sendable, Hashable {
    public var id: Int64
    public var isBuyOrder: Bool
    public var price: Double

    public init(id: Int64, isBuyOrder: Bool, price: Double) {
        self.id = id
        self.isBuyOrder = isBuyOrder
        self.price = price
    }
}

/// Where an open order stands among the orders of its side in its region: `FIRST OF 10`,
/// `2ND OF 22 · +0.5%`, and whether it has been undercut or outbid.
public struct OrderBookPosition: Sendable, Hashable {
    /// 1 when no order of the same side is strictly better.
    public var rank: Int
    /// Orders of the same side, this one included even when the book does not list it yet.
    public var count: Int
    /// The best price of the side, this order included.
    public var bestPrice: Double
    /// The best other order, if it is strictly better than this one.
    public var bestOrderID: Int64?
    /// This order's price against the best, as a fraction: `+0.005` for a sell 0.5% above the
    /// cheapest, `-0.02` for a buy 2% below the highest. 0 when first.
    public var gapToBest: Double

    public var isFirst: Bool { rank == 1 }

    /// The book's position of `order` among `book`'s orders of the same side. Ties do not
    /// count as better: an order matching the best price is still first.
    ///
    /// `ownOrderIDs` are the character's other orders: they are left out, so an order is never
    /// flagged undercut or outbid by the same pilot's cheaper (or higher) one.
    public init(of order: CharacterOrder, in book: [BookOrder], ownOrderIDs: Set<Int64> = []) {
        let side = book.filter {
            $0.isBuyOrder == order.isBuyOrder && $0.id != order.id && !ownOrderIDs.contains($0.id)
        }
        let better = side.filter { order.isBuyOrder ? $0.price > order.price : $0.price < order.price }
        rank = better.count + 1
        count = side.count + 1
        let best = order.isBuyOrder ? better.max { $0.price < $1.price } : better.min { $0.price < $1.price }
        bestOrderID = best?.id
        bestPrice = best?.price ?? order.price
        gapToBest = bestPrice > 0 ? order.price / bestPrice - 1 : 0
    }
}

/// What the order list flags an open order with, most urgent first.
public enum OrderFlag: String, Sendable, Hashable {
    /// A sell order with a cheaper one in its region.
    case undercut
    /// A buy order with a higher one in its region.
    case outbid
    case expiringSoon
}

extension CharacterOrder {
    /// The flag to show, if any. `position` is `nil` while the region's book is not known —
    /// the order is then flagged only for its time.
    public func flag(position: OrderBookPosition?, now: Date) -> OrderFlag? {
        guard state == .open else { return nil }
        if let position, !position.isFirst {
            return isBuyOrder ? .outbid : .undercut
        }
        return isExpiringSoon(at: now) ? .expiringSoon : nil
    }
}
