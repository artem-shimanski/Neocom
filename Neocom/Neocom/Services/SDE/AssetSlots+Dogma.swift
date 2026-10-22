import AssetsKit
import DogmaKit

// Ship hull numbers for the asset screens, read from DogmaKit's `TypeCatalog` instead of the SDE
// database. A separate file keeps DogmaKit's `TypeID` from colliding with SDEKit's.

nonisolated extension AssetTypeInfo.Slots {
    /// The slot counts and bay sizes of a hull, or `nil` for an unknown type.
    init?(shipTypeID: Int64, catalog: TypeCatalog) {
        let typeID = TypeID(rawValue: UInt32(clamping: shipTypeID))
        guard catalog.contains(typeID) else { return nil }
        func count(_ attribute: AttributeID) -> Int {
            Int(catalog.attribute(attribute, of: typeID) ?? 0)
        }
        self.init(high: count(.hiSlots),
                  medium: count(.medSlots),
                  low: count(.lowSlots),
                  rig: count(.rigSlots),
                  subsystem: count(.maxSubSystems),
                  service: count(.serviceSlots),
                  droneCapacity: catalog.attribute(.droneCapacity, of: typeID),
                  fighterCapacity: catalog.attribute(.fighterCapacity, of: typeID))
    }
}

nonisolated extension AssetTypeInfo.SlotModifiers {
    /// The high, medium and low slots a subsystem adds to its hull, or `nil` for an unknown type.
    init?(subsystemTypeID: Int64, catalog: TypeCatalog) {
        let typeID = TypeID(rawValue: UInt32(clamping: subsystemTypeID))
        guard catalog.contains(typeID) else { return nil }
        func count(_ attribute: AttributeID) -> Int {
            Int(catalog.attribute(attribute, of: typeID) ?? 0)
        }
        self.init(high: count(.hiSlotModifier), medium: count(.medSlotModifier), low: count(.lowSlotModifier))
    }
}

nonisolated extension AssetTypeInfo {
    /// The SDE category of subsystems.
    private static let subsystemCategory: Int64 = 32

    /// Fills in `slots` for every ship type in `types` and `slotModifiers` for every subsystem.
    /// Uses one catalog for all types, since opening it maps a file.
    static func addingSlots(to types: [Int64: AssetTypeInfo]) -> [Int64: AssetTypeInfo] {
        guard let catalog = try? TypeCatalog() else { return types }
        var result = types
        for (id, info) in types {
            switch info.categoryID {
            case AssetCategory.ship:
                result[id]?.slots = AssetTypeInfo.Slots(shipTypeID: id, catalog: catalog)
            case subsystemCategory:
                result[id]?.slotModifiers = AssetTypeInfo.SlotModifiers(subsystemTypeID: id, catalog: catalog)
            default:
                break
            }
        }
        return result
    }
}
