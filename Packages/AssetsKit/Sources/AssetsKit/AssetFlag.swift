import Foundation

/// How the index reads ESI's `location_flag`.
enum AssetFlag {
    /// Flags that mean "lying loose in whatever holds it": a station hangar, the inside of a
    /// container. Items under these are sorted into category sections.
    static let looseFlags: Set<String> = ["Hangar", "HangarAll", "Unlocked", "Locked", "AutoFit"]

    /// The ship section a flag names, if it names one.
    static func shipSection(_ flag: String) -> AssetSection.Kind? {
        switch flag {
        case "DroneBay": return .droneBay
        case "FighterBay": return .fighterBay
        case "Cargo": return .cargo
        default: break
        }
        if flag.hasPrefix("FighterTube") { return .fighterBay }
        for (prefix, kind) in racks where flag.hasPrefix(prefix) {
            if Int(flag.dropFirst(prefix.count)) != nil { return kind }
        }
        return nil
    }

    /// Racks by flag prefix. `SubSystemSlot` before `SubSystemBay` cannot collide: the number
    /// after the prefix is checked.
    private static let racks: [(String, AssetSection.Kind)] = [
        ("HiSlot", .highSlots),
        ("MedSlot", .mediumSlots),
        ("LoSlot", .lowSlots),
        ("RigSlot", .rigSlots),
        ("SubSystemSlot", .subsystemSlots),
        ("ServiceSlot", .serviceSlots),
    ]

    /// Flags that go into an ESI fitting.
    static func isFittingFlag(_ flag: String) -> Bool {
        switch shipSection(flag) {
        case .highSlots, .mediumSlots, .lowSlots, .rigSlots, .subsystemSlots, .serviceSlots,
             .droneBay, .fighterBay:
            true
        default:
            false
        }
    }

    /// `"CapsuleerDeliveries"` → `"Capsuleer Deliveries"`, `"SpecializedFuelBay"` →
    /// `"Fuel Bay"`.
    static func title(of flag: String) -> String {
        var raw = Substring(flag)
        if raw.hasPrefix("Specialized"), raw.count > "Specialized".count {
            raw = raw.dropFirst("Specialized".count)
        }
        var result = ""
        var previous: Character?
        for character in raw {
            if let previous {
                let boundary = (character.isUppercase && (previous.isLowercase || previous.isNumber))
                    || (character.isNumber && !previous.isNumber)
                if boundary { result.append(" ") }
            }
            result.append(character)
            previous = character
        }
        return result
    }

    /// The fixed title of a section kind; categories carry their own name.
    static func title(of kind: AssetSection.Kind, categoryName: String?) -> String {
        switch kind {
        case .ships: "Ships"
        case .containers: "Containers"
        case let .category(id):
            AssetCategory.sections.first { $0.id == id }?.title ?? categoryName ?? "Other"
        case let .flag(flag): title(of: flag)
        case .highSlots: "High Slots"
        case .mediumSlots: "Medium Slots"
        case .lowSlots: "Low Slots"
        case .rigSlots: "Rigs"
        case .subsystemSlots: "Subsystems"
        case .serviceSlots: "Service Slots"
        case .droneBay: "Drone Bay"
        case .fighterBay: "Fighter Bay"
        case .cargo: "Cargo"
        case let .hold(flag): title(of: flag)
        }
    }

    /// Sort key of a section: ships and containers first, then a ship's racks and bays in
    /// the order the game shows them, then categories, then everything filed by flag.
    static func rank(of kind: AssetSection.Kind) -> Int {
        switch kind {
        case .ships: 0
        case .containers: 1
        case .highSlots: 10
        case .mediumSlots: 11
        case .lowSlots: 12
        case .rigSlots: 13
        case .subsystemSlots: 14
        case .serviceSlots: 15
        case .droneBay: 16
        case .fighterBay: 17
        case .cargo: 18
        case .hold: 19
        case let .category(id):
            AssetCategory.sections.firstIndex { $0.id == id }.map { 100 + $0 } ?? 500
        case .flag: 1000
        }
    }
}
