import Foundation

// Plain data the index is built from; independent of ESI and the SDE types.

/// One record of `/characters/{id}/assets`, as the server sends it.
///
/// `locationFlag` and `locationType` stay raw strings so that an unknown flag neither breaks a
/// cached file nor gets dropped; the index files it under a section named after it.
public struct AssetRecord: Codable, Sendable, Hashable {
    public var itemID: Int64
    public var typeID: Int64
    /// A station, a structure, a solar system — or another item's `itemID` when this one is
    /// inside a ship or a container.
    public var locationID: Int64
    /// `"Hangar"`, `"HiSlot0"`, `"Cargo"`, `"Unlocked"`, …
    public var locationFlag: String
    /// `"station"`, `"solar_system"`, `"item"` or `"other"`.
    public var locationType: String
    public var quantity: Int64
    public var isSingleton: Bool
    public var isBlueprintCopy: Bool

    public init(itemID: Int64, typeID: Int64, locationID: Int64, locationFlag: String,
                locationType: String, quantity: Int64, isSingleton: Bool, isBlueprintCopy: Bool = false) {
        self.itemID = itemID
        self.typeID = typeID
        self.locationID = locationID
        self.locationFlag = locationFlag
        self.locationType = locationType
        self.quantity = quantity
        self.isSingleton = isSingleton
        self.isBlueprintCopy = isBlueprintCopy
    }
}

/// A root location (one that is not an item of the character), as far as it could be named.
public struct AssetLocationInfo: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case station
        case structure
        /// A structure that answered `403`: the character has items there but no docking
        /// access, so neither its name nor its system is known.
        case structureNoAccess
        case solarSystem
        /// Anything else: an id that answered neither as a station nor as a structure, or one
        /// that was never asked about.
        case unknown
    }

    public var id: Int64
    public var kind: Kind
    public var name: String?
    public var solarSystemID: Int64?
    /// The station's or structure's own type — an NPC station type, a Raitaru, an Athanor —
    /// when ESI provides it. Optional: older cached files lack it.
    public var typeID: Int64?

    public init(id: Int64, kind: Kind, name: String? = nil, solarSystemID: Int64? = nil, typeID: Int64? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.solarSystemID = solarSystemID
        self.typeID = typeID
    }

    /// The assumed location of an unnamed root, from `location_type` and the id ranges.
    public static func guess(id: Int64, locationType: String) -> AssetLocationInfo {
        switch AssetIDRange.classify(id, locationType: locationType) {
        case .station:
            AssetLocationInfo(id: id, kind: .station)
        case .solarSystem:
            AssetLocationInfo(id: id, kind: .solarSystem, solarSystemID: id)
        case .structure, .other:
            AssetLocationInfo(id: id, kind: .unknown)
        }
    }
}

/// What kind of place an id denotes, from ESI's `location_type` and CCP's id ranges.
public enum AssetIDRange: Sendable, Hashable {
    case station
    case solarSystem
    /// Possibly an Upwell structure: worth asking `/universe/structures/{id}` about.
    case structure
    case other

    public static let stations: Range<Int64> = 60_000_000..<64_000_000
    public static let solarSystems: Range<Int64> = 30_000_000..<33_000_000
    /// Upwell structure ids start here. Item ids share the range, so only a root id at or above
    /// this is a structure candidate.
    public static let structuresStart: Int64 = 1_000_000_000_000

    public static func classify(_ id: Int64, locationType: String) -> AssetIDRange {
        switch locationType {
        case "station":
            return .station
        case "solar_system":
            return .solarSystem
        default:
            if stations.contains(id) { return .station }
            if solarSystems.contains(id) { return .solarSystem }
            if id >= structuresStart { return .structure }
            return .other
        }
    }
}

/// A solar system as the location list draws it.
public struct AssetSolarSystem: Codable, Sendable, Hashable {
    public var name: String
    public var securityStatus: Double
    public var regionID: Int64?
    public var regionName: String

    public init(name: String, securityStatus: Double, regionID: Int64? = nil, regionName: String) {
        self.name = name
        self.securityStatus = securityStatus
        self.regionID = regionID
        self.regionName = regionName
    }
}

/// What the static data says about one type, supplied by the caller.
public struct AssetTypeInfo: Codable, Sendable, Hashable {
    /// Slot counts and bay sizes of a ship hull — the denominators of the ship screen.
    public struct Slots: Codable, Sendable, Hashable {
        public var high: Int
        public var medium: Int
        public var low: Int
        public var rig: Int
        public var subsystem: Int
        public var service: Int
        /// m³.
        public var droneCapacity: Double?
        /// m³.
        public var fighterCapacity: Double?

        public init(high: Int = 0, medium: Int = 0, low: Int = 0, rig: Int = 0, subsystem: Int = 0,
                    service: Int = 0, droneCapacity: Double? = nil, fighterCapacity: Double? = nil) {
            self.high = high
            self.medium = medium
            self.low = low
            self.rig = rig
            self.subsystem = subsystem
            self.service = service
            self.droneCapacity = droneCapacity
            self.fighterCapacity = fighterCapacity
        }
    }

    /// What a subsystem adds to the hull it is fitted to. A Strategic Cruiser's hull has no
    /// high, medium or low slots of its own: they all come from its subsystems.
    public struct SlotModifiers: Codable, Sendable, Hashable {
        public var high: Int
        public var medium: Int
        public var low: Int

        public init(high: Int = 0, medium: Int = 0, low: Int = 0) {
            self.high = high
            self.medium = medium
            self.low = low
        }
    }

    public var typeID: Int64
    public var name: String
    public var groupID: Int64
    public var groupName: String
    public var categoryID: Int64
    public var categoryName: String
    /// m³ of one unit.
    public var volume: Double?
    /// Cargo hold (or container) size, m³.
    public var capacity: Double?
    /// Ships only.
    public var slots: Slots?
    /// Subsystems only: the slots they add to the ship they are fitted in.
    public var slotModifiers: SlotModifiers?

    public init(typeID: Int64, name: String, groupID: Int64, groupName: String, categoryID: Int64,
                categoryName: String, volume: Double? = nil, capacity: Double? = nil, slots: Slots? = nil,
                slotModifiers: SlotModifiers? = nil) {
        self.typeID = typeID
        self.name = name
        self.groupID = groupID
        self.groupName = groupName
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.volume = volume
        self.capacity = capacity
        self.slots = slots
        self.slotModifiers = slotModifiers
    }
}

/// Well-known SDE ids the index needs to tell ships, containers and charges apart.
public enum AssetCategory {
    public static let ship: Int64 = 6
    public static let module: Int64 = 7
    public static let charge: Int64 = 8
    public static let blueprint: Int64 = 9

    /// Cargo Container, Secure Cargo Container, Audit Log Secure Container, Freight Container.
    public static let containerGroups: Set<Int64> = [12, 340, 448, 649]

    /// The Asset Safety Wrap, a container type that may be missing from the static data.
    public static let assetSafetyWrap: Int64 = 60

    /// Category sections of a location or container, in display order, with plural titles (the
    /// SDE names are singular). Unlisted categories follow, by SDE name.
    static let sections: [(id: Int64, title: String)] = [
        (7, "Modules"),
        (32, "Subsystems"),
        (18, "Drones"),
        (87, "Fighters"),
        (8, "Charges"),
        (20, "Implants"),
        (16, "Skills"),
        (9, "Blueprints"),
        (34, "Ancient Relics"),
        (4, "Materials"),
        (17, "Commodities"),
        (43, "Planetary Commodities"),
        (41, "Planetary Industry"),
        (25, "Asteroids"),
        (35, "Decryptors"),
        (66, "Structure Modules"),
        (65, "Structures"),
        (22, "Deployables"),
        (23, "Starbases"),
        (24, "Reactions"),
        (30, "Apparel"),
        (91, "SKINs"),
        (63, "Special Edition Assets"),
    ]
}
