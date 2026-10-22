import BusinessKit
import SDEKit
import SwiftUI

/// How the Market Orders screens write what an order is and what is wrong with it.
enum OrdersText {
    /// `FILLED`, `UNDERCUT`, `OPEN`: the one word an order wears, and its colour.
    struct Badge {
        var title: String
        var color: Color
    }

    static func badge(for order: CharacterOrder, flag: OrderFlag?) -> Badge? {
        switch order.outcome {
        case .filled: return Badge(title: String(localized: "Filled"), color: .hudOk)
        case .expired: return Badge(title: String(localized: "Expired"), color: .hudInkMuted)
        case .cancelled: return Badge(title: String(localized: "Cancelled"), color: .hudInkMuted)
        case .open:
            guard let flag else { return nil }
            return Badge(title: title(of: flag), color: .hudWarn)
        }
    }

    static func title(of flag: OrderFlag) -> String {
        switch flag {
        case .undercut: String(localized: "Undercut")
        case .outbid: String(localized: "Outbid")
        case .expiringSoon: String(localized: "Expires soon")
        }
    }

    static func side(_ order: CharacterOrder) -> String {
        order.isBuyOrder ? String(localized: "Buy") : String(localized: "Sell")
    }

    /// `3 / 10`.
    static func quantity(_ order: CharacterOrder) -> String {
        "\(MarketFormat.quantity(order.volumeRemain)) / \(MarketFormat.quantity(order.volumeTotal))"
    }

    /// The reach of a buy order for the facts list: `Station`, `Solar system`, `5 jumps`.
    static func rangeLong(_ raw: String) -> String {
        switch raw {
        case "station": String(localized: "Station")
        case "solarsystem": String(localized: "Solar system")
        case "region": String(localized: "Region")
        default: Int(raw).map { String(localized: "\($0) jumps") } ?? raw
        }
    }

    /// Parts joined with a middle dot, each keeping its own colour.
    static func joined(_ parts: [Text]) -> Text {
        HUDPlaceBlock.joined(parts) ?? Text(verbatim: "")
    }

    /// `RENS 0.9`, the security in its own colour.
    static func system(_ system: MarketSystemRow) -> Text {
        HUDPlaceBlock.system(name: system.name, security: system.securityStatus)
    }
}
