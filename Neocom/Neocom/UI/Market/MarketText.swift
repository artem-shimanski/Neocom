import LiteRow
import LiteRowUI
import MarketKit
import SDEKit
import SwiftUI

/// How the Market screens write their figures, shared by the price card and the market screen.
nonisolated enum MarketFormat {
    /// A change as a fraction, signed and with a true minus: `−5.6%`, `+0.4%`, `0.0%`.
    static func signedPercent(_ fraction: Double) -> String {
        percent(fraction, plus: "+")
    }

    /// A share as a fraction, unsigned unless negative: the spread, `16.7%`.
    static func percent(_ fraction: Double) -> String {
        percent(fraction, plus: "")
    }

    /// The sign is set here rather than by the formatter, as locales differ in the minus character;
    /// only the magnitude is formatted.
    private static func percent(_ fraction: Double, plus: String) -> String {
        let value = fraction * 100
        let magnitude = abs(value)
        let text = magnitude.formatted(.number.precision(.fractionLength(1)))
        // What rounds to zero gets no sign: `0.0%`, never `−0.0%`.
        guard (magnitude * 10).rounded(.toNearestOrEven) > 0 else { return "\(text)%" }
        return "\(value < 0 ? "−" : plus)\(text)%"
    }

    /// Units, grouped: `1 250`.
    static func quantity(_ value: Int64) -> String {
        value.formatted(.number)
    }

    /// Units traded per day, a tenth kept for the items that trade a few a day.
    static func volumePerDay(_ value: Double) -> String {
        value >= 1000 ? ISK.compact(value) : value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Gate jumps from the pilot: `HERE`, `2 J`.
    static func jumps(_ count: Int) -> String {
        count == 0 ? String(localized: "Here") : String(localized: "\(count) J", comment: "Jumps, abbreviated")
    }

    /// The reach of a buy order, the way the game abbreviates it: `STATION`, `SYSTEM`,
    /// `REGION`, `5 J`. A value ESI adds later is written as it comes.
    static func range(_ raw: String) -> String {
        switch raw {
        case "station": String(localized: "Station")
        case "solarsystem": String(localized: "System")
        case "region": String(localized: "Region")
        default: Int(raw).map { String(localized: "\($0) J", comment: "Jumps, abbreviated") } ?? raw
        }
    }

    static func regionID(_ id: Int64) -> RegionID { RegionID(rawValue: UInt32(clamping: id)) }
    static func systemID(_ id: Int64) -> SolarSystemID { SolarSystemID(rawValue: UInt32(clamping: id)) }
}

/// The name of a market region and, for one with a trade hub, its hub system, read from the
/// static data.
struct MarketRegionName<Content: View>: View {
    @LiteQuery private var regions: [MarketRegionRow]
    @LiteQuery private var hubs: [MarketSystemRow]
    private let content: (_ region: String?, _ hub: MarketSystemRow?) -> Content

    /// `hubSystemID` is the hub to name, usually `MarketRegionPreference.hubSystemID(forRegion:)`;
    /// `nil` for none.
    init(regionID: Int64, hubSystemID: Int64?,
         @ViewBuilder content: @escaping (_ region: String?, _ hub: MarketSystemRow?) -> Content) {
        self.content = content
        _regions = LiteQuery(MarketBrowser.regions([MarketFormat.regionID(regionID)]))
        _hubs = LiteQuery(hubSystemID.map { MarketBrowser.systems([MarketFormat.systemID($0)]) })
    }

    var body: some View {
        content(regions.first?.name, hubs.first)
    }
}

extension SDEStore {
    var database: SDEDatabase? {
        if case let .ready(database) = state { return database }
        return nil
    }
}
