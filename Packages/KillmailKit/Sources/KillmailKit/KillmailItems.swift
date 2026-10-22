// What the victim lost, by section, and what it was worth.

import Foundation

/// Where an item sat, from its inventory flag.
public enum KillmailSection: Int, Codable, Sendable, Hashable, CaseIterable, Comparable {
    case high
    case medium
    case low
    case rig
    case subsystem
    case service
    case droneBay
    case fighterBay
    case cargo
    case implant
    /// Every other hold and bay (fuel, ore, ship and fleet hangars, …).
    case other

    /// 27-34 high slots, 19-26 medium, 11-18 low, 92-99 rigs, 125-132 subsystems, 164-171
    /// service slots, 87 drone bay, 158 fighter bay, 5 cargo, 89 implants.
    public static func of(flag: Int64) -> KillmailSection {
        switch flag {
        case 27...34: .high
        case 19...26: .medium
        case 11...18: .low
        case 92...99: .rig
        case 125...132: .subsystem
        case 164...171: .service
        case 87: .droneBay
        case 158: .fighterBay
        case 5: .cargo
        case 89: .implant
        default: .other
        }
    }

    /// A rack of slots: one module per flag, and a charge loaded into it shares the flag.
    public var isSlotRack: Bool {
        switch self {
        case .high, .medium, .low, .rig, .subsystem, .service: true
        default: false
        }
    }

    public static func < (lhs: KillmailSection, rhs: KillmailSection) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One row of a section: an item, how deep it sits, and whether it is a charge loaded into the
/// module above it.
public struct KillmailItemRow: Sendable, Hashable {
    public var item: KillmailItem
    /// 0 for a top-level item; 1 for a loaded charge or a container's contents, deeper for a
    /// container inside a container.
    public var depth: Int
    /// A charge in the same slot as the module it is loaded into.
    public var isLoaded: Bool

    public init(item: KillmailItem, depth: Int, isLoaded: Bool = false) {
        self.item = item
        self.depth = depth
        self.isLoaded = isLoaded
    }

    public var isNested: Bool { depth > 0 }
}

/// One section of the killmail: `HIGH SLOTS 4/4`, `DRONE BAY 4 TYPES`, `CARGO 4 ITEMS`.
public struct KillmailItemGroup: Sendable, Hashable, Identifiable {
    public var section: KillmailSection
    public var rows: [KillmailItemRow]

    public init(section: KillmailSection, rows: [KillmailItemRow]) {
        self.section = section
        self.rows = rows
    }

    public var id: KillmailSection { section }

    /// Rows that are not nested: in a rack, the modules — what the `4/4` counts.
    public var topLevelCount: Int { rows.count { !$0.isNested } }
}

extension Killmail {
    /// The items by section, in `KillmailSection` order, empty sections left out.
    ///
    /// In a rack the items are ordered by slot; within a slot the module comes first and its
    /// loaded charge follows, nested (`isLoaded`). ESI gives both the same flag; `isCharge`
    /// tells them apart (SDE category 8). Without it, the first single item in a slot is the
    /// module and the rest are charges. Elsewhere items keep ESI's order. A container's
    /// contents follow it, one level deeper.
    public func itemGroups(isCharge: ((Int64) -> Bool)? = nil) -> [KillmailItemGroup] {
        var bySection: [KillmailSection: [KillmailItem]] = [:]
        for item in victim.items {
            bySection[KillmailSection.of(flag: item.flag), default: []].append(item)
        }
        return KillmailSection.allCases.compactMap { section in
            guard let items = bySection[section], !items.isEmpty else { return nil }
            var rows: [KillmailItemRow] = []
            if section.isSlotRack {
                // Stable by flag: Dictionary(grouping:) would lose the order within a slot.
                let flags = Array(Set(items.map(\.flag))).sorted()
                for flag in flags {
                    let inSlot = items.filter { $0.flag == flag }
                    let moduleIndex: Int? = if let isCharge {
                        inSlot.firstIndex { !isCharge($0.typeID) }
                    } else {
                        inSlot.firstIndex { $0.quantity == 1 } ?? (inSlot.count == 1 ? 0 : nil)
                    }
                    let charges: (KillmailItem) -> Bool = { item in
                        if let isCharge { return isCharge(item.typeID) }
                        return true
                    }
                    if let moduleIndex {
                        Self.append(inSlot[moduleIndex], depth: 0, isLoaded: false, to: &rows)
                    }
                    for (index, item) in inSlot.enumerated() where index != moduleIndex {
                        let loaded = moduleIndex != nil && charges(item)
                        Self.append(item, depth: loaded ? 1 : 0, isLoaded: loaded, to: &rows)
                    }
                }
            } else {
                for item in items {
                    Self.append(item, depth: 0, isLoaded: false, to: &rows)
                }
            }
            return KillmailItemGroup(section: section, rows: rows)
        }
    }

    private static func append(_ item: KillmailItem, depth: Int, isLoaded: Bool, to rows: inout [KillmailItemRow]) {
        rows.append(KillmailItemRow(item: item, depth: depth, isLoaded: isLoaded))
        for child in item.items {
            append(child, depth: depth + 1, isLoaded: false, to: &rows)
        }
    }
}

// MARK: - Value

/// What a killmail was worth: an estimate from average prices. The hull counts as destroyed.
public struct KillmailValue: Codable, Sendable, Hashable {
    public var destroyed: Double
    public var dropped: Double

    public init(destroyed: Double = 0, dropped: Double = 0) {
        self.destroyed = destroyed
        self.dropped = dropped
    }

    public var total: Double { destroyed + dropped }

    public static func + (lhs: KillmailValue, rhs: KillmailValue) -> KillmailValue {
        KillmailValue(destroyed: lhs.destroyed + rhs.destroyed, dropped: lhs.dropped + rhs.dropped)
    }
}

extension KillmailItem {
    /// The stack's own worth, its contents not included: quantities times `price`. A type
    /// without a price, and a blueprint copy, is worth nothing.
    public func value(price: (Int64) -> Double?) -> KillmailValue {
        guard !isBlueprintCopy, let unit = price(typeID) else { return KillmailValue() }
        return KillmailValue(destroyed: Double(quantityDestroyed) * unit, dropped: Double(quantityDropped) * unit)
    }

    /// The stack and everything inside it.
    public func totalValue(price: (Int64) -> Double?) -> KillmailValue {
        items.reduce(value(price: price)) { $0 + $1.totalValue(price: price) }
    }
}

extension Killmail {
    /// The hull (destroyed) and every item, containers' contents included, at `price` — CCP's
    /// average price of a type.
    public func value(price: (Int64) -> Double?) -> KillmailValue {
        let hull = KillmailValue(destroyed: price(victim.shipTypeID) ?? 0)
        return victim.items.reduce(hull) { $0 + $1.totalValue(price: price) }
    }
}

// MARK: - Fit

/// One item of the lost fit, as the fitting tool imports it: ESI's fitting flag name
/// (`HiSlot0`, `DroneBay`, …) and the whole stack, destroyed and dropped alike.
public struct KillmailFitItem: Sendable, Hashable {
    public var typeID: Int64
    public var flag: String
    public var quantity: Int64

    public init(typeID: Int64, flag: String, quantity: Int64) {
        self.typeID = typeID
        self.flag = flag
        self.quantity = quantity
    }
}

extension Killmail {
    /// The fitting flag name of an inventory flag, `nil` for a place a fitting does not keep
    /// (implants, containers' contents, other holds).
    public static func fittingFlag(_ flag: Int64) -> String? {
        switch flag {
        case 27...34: "HiSlot\(flag - 27)"
        case 19...26: "MedSlot\(flag - 19)"
        case 11...18: "LoSlot\(flag - 11)"
        case 92...99: "RigSlot\(flag - 92)"
        case 125...132: "SubSystemSlot\(flag - 125)"
        case 164...171: "ServiceSlot\(flag - 164)"
        case 87: "DroneBay"
        case 158: "FighterBay"
        case 5: "Cargo"
        default: nil
        }
    }

    /// The lost fit: modules, loaded charges, drones and fighters — top-level items only,
    /// stacks split between destroyed and dropped joined back. Empty for a capsule.
    public var fitItems: [KillmailFitItem] {
        guard !isCapsule else { return [] }
        var items: [KillmailFitItem] = []
        for item in victim.items {
            // Cargo is not part of a fit.
            guard let flag = Self.fittingFlag(item.flag), flag != "Cargo", item.quantity > 0 else { continue }
            // One place holds one module, so a type twice in one flag is a split stack.
            if let index = items.firstIndex(where: { $0.typeID == item.typeID && $0.flag == flag }) {
                items[index].quantity += item.quantity
            } else {
                items.append(KillmailFitItem(typeID: item.typeID, flag: flag, quantity: item.quantity))
            }
        }
        return items
    }
}
