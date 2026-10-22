import Foundation

// Query results: structured fields only, formatting is left to the caller.

/// The totals at the top of the Assets screen.
public struct AssetSummary: Sendable, Hashable {
    /// Root locations: stations, structures, systems and places nobody could name.
    public var locations: Int
    /// Asset records — what the game counts as items, a stack being one.
    public var items: Int
    /// Ships, assembled or packaged: the sum of the quantities of ship records.
    public var ships: Int64
    /// Blueprint copy records.
    public var blueprintCopies: Int

    public init(locations: Int = 0, items: Int = 0, ships: Int64 = 0, blueprintCopies: Int = 0) {
        self.locations = locations
        self.items = items
        self.ships = ships
        self.blueprintCopies = blueprintCopies
    }
}

/// A root location with what is in it, counted through every ship and container.
public struct AssetLocation: Identifiable, Sendable, Hashable {
    public var id: Int64
    public var kind: AssetLocationInfo.Kind
    /// The station's or structure's name — or the system's for a solar-system root. `nil`
    /// when nobody could name it (a structure without access, an unknown place).
    public var name: String?
    public var solarSystemID: Int64?
    public var system: AssetSolarSystem?
    /// Every record below, at any depth.
    public var itemCount: Int
    /// Ships below, at any depth: quantities summed, so seven packaged Velators are seven.
    public var shipCount: Int64
    /// Containers (anything that opens and is not a ship) below, at any depth.
    public var containerCount: Int
}

/// The locations of one region, as the Assets screen groups them.
public struct AssetRegion: Identifiable, Sendable, Hashable {
    /// The region's name, or `nil` for the group of places with no known system.
    public var name: String?
    public var locations: [AssetLocation]

    public var id: String { name ?? "" }
}

/// One line of a location, container or ship screen.
///
/// Either one item that opens — an assembled ship, a container — or a stack: every record of
/// the same type (and the same blueprint-copy-ness) in the same section, quantities summed.
public struct AssetRow: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// An assembled ship: opens into its fitting and holds.
        case ship
        /// Anything else that holds items and opens.
        case container
        /// A stack.
        case item
    }

    /// The first record's item id: unique among rows, and the item itself for a row that opens.
    public var id: Int64
    public var itemIDs: [Int64]
    public var kind: Kind
    public var typeID: Int64
    /// The custom name when the item has one, the type name otherwise.
    public var name: String
    public var customName: String?
    public var typeName: String
    public var groupID: Int64
    public var groupName: String
    public var categoryID: Int64
    public var categoryName: String
    public var quantity: Int64
    public var isBlueprintCopy: Bool
    /// Every record of the row is a singleton: an assembled ship or container, a fitted module,
    /// a blueprint. A packaged ship is `false`.
    public var isAssembled: Bool
    /// The raw flag of the first record.
    public var flag: String
    /// Records directly inside (only for a row that opens).
    public var childCount: Int
    /// Records inside at any depth (only for a row that opens).
    public var nestedCount: Int

    public var opens: Bool { kind != .item }
    public var isShipType: Bool { categoryID == AssetCategory.ship }
    public var isCharge: Bool { categoryID == AssetCategory.charge }
}

/// A titled block of rows.
public struct AssetSection: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case ships
        case containers
        case category(Int64)
        /// A station flag that is not the hangar: Deliveries, Asset Safety, … or anything else
        /// the index has no section for. The raw flag.
        case flag(String)
        case highSlots
        case mediumSlots
        case lowSlots
        case rigSlots
        case subsystemSlots
        case serviceSlots
        case droneBay
        case fighterBay
        case cargo
        /// Any other hold of a ship: Fleet Hangar, Ore Hold, … The raw flag.
        case hold(String)
    }

    public var kind: Kind
    /// English, in natural case ("High Slots", "Modules", "Asset Safety"); the screen may
    /// upper-case it.
    public var title: String
    public var rows: [AssetRow]
    /// The used/total line of a ship section, when the hull's numbers are known.
    public var capacity: AssetCapacity?

    public var id: Kind { kind }
}

public enum AssetCapacity: Sendable, Hashable {
    /// Modules fitted (charges are not counted) out of the hull's slots.
    case slots(used: Int, total: Int)
    /// m³ taken out of the bay's size.
    case volume(used: Double, total: Double)
}

/// Where an item is: its root location and the ships and containers around it, outermost
/// first.
public struct AssetPath: Sendable, Hashable {
    public var location: AssetLocation?
    public var parents: [AssetRow]
}

/// The hits of one location.
public struct AssetSearchResult: Identifiable, Sendable, Hashable {
    public var location: AssetLocation
    public var hits: [AssetSearchHit]

    public var id: Int64 { location.id }
}

public struct AssetSearchHit: Identifiable, Sendable, Hashable {
    public var row: AssetRow
    /// The ships and containers around the row, outermost first; empty for a row lying in
    /// the location itself.
    public var parents: [AssetRow]

    public var id: Int64 { row.id }
}

/// An assembled ship as a game fitting describes it: the hull and what sits in its slots and
/// bays. The flags are ESI's raw strings, ready for the app's `ESIFitting`.
public struct AssetFitting: Sendable, Hashable {
    public struct Item: Sendable, Hashable {
        public var typeID: Int64
        public var flag: String
        public var quantity: Int64

        public init(typeID: Int64, flag: String, quantity: Int64) {
            self.typeID = typeID
            self.flag = flag
            self.quantity = quantity
        }
    }

    public var shipItemID: Int64
    public var shipTypeID: Int64
    public var name: String
    public var items: [Item]
}
