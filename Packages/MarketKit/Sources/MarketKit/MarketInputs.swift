import Foundation

// Plain data the market math works on, independent of ESI and the SDE.

/// One order of `/markets/{region_id}/orders`, with only what the screens draw.
public struct MarketOrder: Codable, Sendable, Hashable, Identifiable {
    /// The order id.
    public var id: Int64
    public var isBuyOrder: Bool
    /// ISK per unit.
    public var price: Double
    /// Units still on offer (sell) or still wanted (buy).
    public var volumeRemain: Int64
    /// Units the order was placed for.
    public var volumeTotal: Int64
    /// The smallest quantity a single trade with this order may be. Always 1 for sell orders;
    /// a buy order can ask for more.
    public var minVolume: Int64
    /// A station (60000000–64000000) or a player-owned structure.
    public var locationID: Int64
    public var systemID: Int64
    /// `"station"`, `"solarsystem"`, `"region"` or a number of jumps (`"1"`, `"5"`, …). Only
    /// meaningful for buy orders: how far from `locationID` a seller may be. Kept as a raw string
    /// so unknown values survive decoding.
    public var range: String
    public var issued: Date

    /// `volumeTotal` defaults to `volumeRemain`: an order nothing has been traded against yet.
    public init(id: Int64, isBuyOrder: Bool, price: Double, volumeRemain: Int64, volumeTotal: Int64? = nil,
                minVolume: Int64 = 1, locationID: Int64, systemID: Int64, range: String = "station",
                issued: Date = .distantPast) {
        self.id = id
        self.isBuyOrder = isBuyOrder
        self.price = price
        self.volumeRemain = volumeRemain
        self.volumeTotal = volumeTotal ?? volumeRemain
        self.minVolume = minVolume
        self.locationID = locationID
        self.systemID = systemID
        self.range = range
        self.issued = issued
    }

    /// The id range of NPC stations; any other location is a player-owned structure.
    public static let stationIDs: ClosedRange<Int64> = 60_000_000...63_999_999

    public var isInStation: Bool { Self.stationIDs.contains(locationID) }
}

/// One day of `/markets/{region_id}/history`.
public struct MarketHistoryDay: Codable, Sendable, Hashable, Identifiable {
    /// Midnight UTC of the day.
    public var date: Date
    /// The volume-weighted average price of the day's trades.
    public var average: Double
    public var lowest: Double
    public var highest: Double
    /// Units traded.
    public var volume: Int64
    /// Trades made.
    public var orderCount: Int64

    public var id: Date { date }

    public init(date: Date, average: Double, lowest: Double, highest: Double, volume: Int64, orderCount: Int64) {
        self.date = date
        self.average = average
        self.lowest = lowest
        self.highest = highest
        self.volume = volume
        self.orderCount = orderCount
    }

    /// ESI's `"2026-10-15"` as midnight UTC; `nil` for anything else.
    public static func date(fromESI string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(calendar: .utc, timeZone: .gmt, year: parts[0], month: parts[1], day: parts[2]).date
    }
}

extension Calendar {
    /// Gregorian in UTC: the calendar EVE's market days are counted in.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}
