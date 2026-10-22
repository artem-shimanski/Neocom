import AssetsKit
import Foundation

// Titles in the app's language; categories and flags missing from the tables keep the
// package's title.

extension AssetSection {
    var localizedTitle: String {
        switch kind {
        case .ships: return String(localized: "Ships", comment: "Section of assets: ships.")
        case .containers: return String(localized: "Containers", comment: "Section of assets: containers.")
        case .highSlots: return String(localized: "High Slots", comment: "EVE inventory flag name.")
        case .mediumSlots: return String(localized: "Medium Slots", comment: "EVE inventory flag name.")
        case .lowSlots: return String(localized: "Low Slots", comment: "EVE inventory flag name.")
        case .rigSlots: return String(localized: "Rigs", comment: "EVE inventory flag name.")
        case .subsystemSlots: return String(localized: "Subsystems", comment: "EVE inventory flag name.")
        case .serviceSlots: return String(localized: "Service Slots", comment: "EVE inventory flag name.")
        case .droneBay: return String(localized: "Drone Bay", comment: "EVE inventory flag name.")
        case .fighterBay: return String(localized: "Fighter Bay", comment: "EVE inventory flag name.")
        case .cargo: return String(localized: "Cargo", comment: "EVE inventory flag name.")
        case let .category(id): return Self.categoryTitle(id) ?? (title == "Other" ? String(localized: "Other") : title)
        case let .flag(flag), let .hold(flag): return Self.flagTitle(flag) ?? title
        }
    }

    private static func categoryTitle(_ id: Int64) -> String? {
        switch id {
        case 7: return String(localized: "Modules", comment: "Plural EVE category name, a section of assets.")
        case 32: return String(localized: "Subsystems", comment: "Plural EVE category name, a section of assets.")
        case 18: return String(localized: "Drones", comment: "Plural EVE category name, a section of assets.")
        case 87: return String(localized: "Fighters", comment: "Plural EVE category name, a section of assets.")
        case 8: return String(localized: "Charges", comment: "Plural EVE category name, a section of assets.")
        case 20: return String(localized: "Implants", comment: "Plural EVE category name, a section of assets.")
        case 16: return String(localized: "Skills", comment: "Plural EVE category name, a section of assets.")
        case 9: return String(localized: "Blueprints", comment: "Plural EVE category name, a section of assets.")
        case 34: return String(localized: "Ancient Relics", comment: "Plural EVE category name, a section of assets.")
        case 4: return String(localized: "Materials", comment: "Plural EVE category name, a section of assets.")
        case 17: return String(localized: "Commodities", comment: "Plural EVE category name, a section of assets.")
        case 43: return String(localized: "Planetary Commodities", comment: "Plural EVE category name, a section of assets.")
        case 41: return String(localized: "Planetary Industry", comment: "Plural EVE category name, a section of assets.")
        case 25: return String(localized: "Asteroids", comment: "Plural EVE category name, a section of assets.")
        case 35: return String(localized: "Decryptors", comment: "Plural EVE category name, a section of assets.")
        case 66: return String(localized: "Structure Modules", comment: "Plural EVE category name, a section of assets.")
        case 65: return String(localized: "Structures", comment: "Plural EVE category name, a section of assets.")
        case 22: return String(localized: "Deployables", comment: "Plural EVE category name, a section of assets.")
        case 23: return String(localized: "Starbases", comment: "Plural EVE category name, a section of assets.")
        case 24: return String(localized: "Reactions", comment: "Plural EVE category name, a section of assets.")
        case 30: return String(localized: "Apparel", comment: "Plural EVE category name, a section of assets.")
        case 91: return String(localized: "SKINs", comment: "Plural EVE category name, a section of assets.")
        case 63: return String(localized: "Special Edition Assets", comment: "Plural EVE category name, a section of assets.")
        default: return nil
        }
    }

    private static func flagTitle(_ flag: String) -> String? {
        switch flag {
        case "Deliveries": return String(localized: "Deliveries", comment: "EVE inventory flag name.")
        case "CorpDeliveries": return String(localized: "Corp Deliveries", comment: "EVE inventory flag name.")
        case "CapsuleerDeliveries": return String(localized: "Capsuleer Deliveries", comment: "EVE inventory flag name.")
        case "AssetSafety": return String(localized: "Asset Safety", comment: "EVE inventory flag name.")
        case "FleetHangar": return String(localized: "Fleet Hangar", comment: "EVE inventory flag name.")
        case "ShipHangar": return String(localized: "Ship Hangar", comment: "EVE inventory flag name.")
        case "SpecializedOreHold": return String(localized: "Ore Hold", comment: "EVE inventory flag name.")
        case "SpecializedFuelBay": return String(localized: "Fuel Bay", comment: "EVE inventory flag name.")
        case "SpecializedGasHold": return String(localized: "Gas Hold", comment: "EVE inventory flag name.")
        case "SpecializedMineralHold": return String(localized: "Mineral Hold", comment: "EVE inventory flag name.")
        case "SpecializedAmmoHold": return String(localized: "Ammo Hold", comment: "EVE inventory flag name.")
        case "SpecializedCommandCenterHold": return String(localized: "Command Center Hold", comment: "EVE inventory flag name.")
        case "SpecializedPlanetaryCommoditiesHold":
            return String(localized: "Planetary Commodities Hold", comment: "EVE inventory flag name.")
        case "SpecializedMaterialBay": return String(localized: "Material Bay", comment: "EVE inventory flag name.")
        case "SpecializedLargeShipHold": return String(localized: "Large Ship Hold", comment: "EVE inventory flag name.")
        case "SpecializedMediumShipHold": return String(localized: "Medium Ship Hold", comment: "EVE inventory flag name.")
        case "SpecializedSmallShipHold": return String(localized: "Small Ship Hold", comment: "EVE inventory flag name.")
        case "SpecializedIndustrialShipHold": return String(localized: "Industrial Ship Hold", comment: "EVE inventory flag name.")
        case "SpecializedSalvageHold": return String(localized: "Salvage Hold", comment: "EVE inventory flag name.")
        case "SpecializedShipHold": return String(localized: "Ship Hold", comment: "EVE inventory flag name.")
        case "QuafeBay": return String(localized: "Quafe Bay", comment: "EVE inventory flag name.")
        case "FrigateEscapeBay": return String(localized: "Frigate Escape Bay", comment: "EVE inventory flag name.")
        case "StructureDeedBay": return String(localized: "Structure Deed Bay", comment: "EVE inventory flag name.")
        case "BoosterBay": return String(localized: "Booster Bay", comment: "EVE inventory flag name.")
        case "Implant": return String(localized: "Implants", comment: "EVE inventory flag name.")
        case "Skill": return String(localized: "Skills", comment: "EVE inventory flag name.")
        default: return nil
        }
    }
}
