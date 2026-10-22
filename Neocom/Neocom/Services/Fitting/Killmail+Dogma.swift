import AssetsKit
import DogmaKit
import Foundation
import KillmailKit

// Type catalog queries used by the killmail report.

nonisolated extension ESIFitting {
    /// The fit lost on a killmail (`Killmail.fitItems`), as an ESI fitting with id 0.
    init(lostFitOf killmail: Killmail, name: String, description: String = "") {
        self.init(id: 0,
                  name: name,
                  fittingDescription: description,
                  shipTypeID: killmail.victim.shipTypeID,
                  items: killmail.fitItems.map { Item(typeID: $0.typeID, flag: $0.flag, quantity: $0.quantity) })
    }
}

nonisolated extension TypeCatalog {
    /// Whether the type is a charge (category 8); `Killmail.itemGroups(isCharge:)` nests
    /// charges under the module in the same slot.
    func isCharge(_ typeID: Int64) -> Bool {
        categoryID(of: TypeID(rawValue: UInt32(clamping: typeID))) == .charge
    }

    /// The victim hull's slot count for a rack, or `nil` for a non-rack section or an unknown
    /// hull. Strategic cruiser high, medium and low slots include the lost subsystems' modifiers.
    func slotCount(of section: KillmailSection, in killmail: Killmail) -> Int? {
        guard section.isSlotRack,
              let slots = AssetTypeInfo.Slots(shipTypeID: killmail.victim.shipTypeID, catalog: self) else { return nil }
        let modifiers = killmail.victim.items
            .filter { KillmailSection.of(flag: $0.flag) == .subsystem }
            .compactMap { AssetTypeInfo.SlotModifiers(subsystemTypeID: $0.typeID, catalog: self) }
        func total(_ base: Int, _ modifier: (AssetTypeInfo.SlotModifiers) -> Int) -> Int {
            base + modifiers.reduce(0) { $0 + modifier($1) }
        }
        let count = switch section {
        case .high: total(slots.high, \.high)
        case .medium: total(slots.medium, \.medium)
        case .low: total(slots.low, \.low)
        case .rig: slots.rig
        case .subsystem: slots.subsystem
        case .service: slots.service
        default: 0
        }
        return count > 0 ? count : nil
    }
}
