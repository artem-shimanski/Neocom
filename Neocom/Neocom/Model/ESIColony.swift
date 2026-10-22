import Foundation

/// A planetary colony as stored in `ESICache`: the header from `/characters/{id}/planets`, the
/// layout from `/characters/{id}/planets/{planet_id}` and the name from `/universe/planets`.
///
/// Header and layout come from one fetch: the layout's contents and cycle starts are valid only
/// at the header's `lastUpdate`.
nonisolated struct ESIColony: Codable, Sendable, Hashable, Identifiable {
    var planetID: Int64
    /// `nil` when `/universe/planets` could not be reached.
    var planetName: String?
    /// ESI's lower-case spelling: `barren`, `gas`, `ice`, `lava`, `oceanic`, `plasma`,
    /// `storm`, `temperate`.
    var planetType: String
    var solarSystemID: Int64
    var upgradeLevel: Int
    var numberOfPins: Int
    /// When the server last recomputed the colony (the player opened it in the game client).
    /// Any later state is simulated.
    var lastUpdate: Date
    var pins: [Pin]
    var links: [Link]
    var routes: [Route]

    var id: Int64 { planetID }

    struct Pin: Codable, Sendable, Hashable {
        var pinID: Int64
        var typeID: Int64
        var latitude: Double
        var longitude: Double
        var schematicID: Int64?
        var installTime: Date?
        var expiryTime: Date?
        var lastCycleStart: Date?
        var contents: [Item]
        var extractor: Extractor?
    }

    struct Item: Codable, Sendable, Hashable {
        var typeID: Int64
        var amount: Int64
    }

    struct Extractor: Codable, Sendable, Hashable {
        var productTypeID: Int64?
        var cycleTime: Int64?
        var quantityPerCycle: Int64?
        var headCount: Int
    }

    struct Link: Codable, Sendable, Hashable {
        var sourcePinID: Int64
        var destinationPinID: Int64
        var level: Int
    }

    struct Route: Codable, Sendable, Hashable {
        var routeID: Int64
        var sourcePinID: Int64
        var destinationPinID: Int64
        var typeID: Int64
        var quantity: Double
        var waypoints: [Int64]
    }
}

