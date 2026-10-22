//
//  Dogma.swift
//  SDE
//
//  Created by Artem Shimanski on 03.09.2026.
//

import LiteRow

// MARK: - Dogma reference tables
//
// An attribute, effect and unit have two names: the internal one is plain `TEXT`, only
// `displayName` is localized (via `NameID`).

@Table("dogmaAttributeCategories")
public struct DogmaAttributeCategoryInfo: Identifiable {
    @PrimaryKey public var id: AttributeCategoryID
    public var name: String = ""
    public var descriptionID: DescriptionID? = nil
}

@Table("dogmaAttributes")
public struct DogmaAttributeInfo: Identifiable {
    @PrimaryKey public var id: AttributeID
    public var name: String = ""
    public var displayNameID: NameID? = nil
    public var descriptionID: DescriptionID? = nil
    public var tooltipTitleID: NameID? = nil
    public var tooltipDescriptionID: DescriptionID? = nil
    @Index public var attributeCategoryID: AttributeCategoryID? = nil
    public var unitID: UnitID? = nil
    public var iconID: IconID? = nil
    public var defaultValue: Double = 0
    public var minAttributeID: AttributeID? = nil
    public var maxAttributeID: AttributeID? = nil
    public var chargeRechargeTimeID: AttributeID? = nil
    public var dataType: Int = 0
    public var displayWhenZero: Bool = false
    public var highIsGood: Bool = false
    public var stackable: Bool = false
    public var published: Bool = false
}

@Table("dogmaUnits")
public struct DogmaUnitInfo: Identifiable {
    @PrimaryKey public var id: UnitID
    public var name: String = ""
    public var displayNameID: NameID? = nil
    public var descriptionID: DescriptionID? = nil
}

@Table("dogmaEffects")
public struct DogmaEffectInfo: Identifiable {
    @PrimaryKey public var id: EffectID
    public var name: String = ""
    public var displayNameID: NameID? = nil
    public var descriptionID: DescriptionID? = nil
    public var effectCategoryID: Int = 0
    public var iconID: IconID? = nil
    public var guid: String? = nil
    public var dischargeAttributeID: AttributeID? = nil
    public var durationAttributeID: AttributeID? = nil
    public var falloffAttributeID: AttributeID? = nil
    public var rangeAttributeID: AttributeID? = nil
    public var trackingSpeedAttributeID: AttributeID? = nil
    public var resistanceAttributeID: AttributeID? = nil
    public var fittingUsageChanceAttributeID: AttributeID? = nil
    public var npcActivationChanceAttributeID: AttributeID? = nil
    public var npcUsageChanceAttributeID: AttributeID? = nil
    public var distribution: Int? = nil
    public var disallowAutoRepeat: Bool = false
    public var electronicChance: Bool = false
    public var isAssistance: Bool = false
    public var isOffensive: Bool = false
    public var isWarpSafe: Bool = false
    public var propulsionChance: Bool = false
    public var rangeChance: Bool = false
    public var published: Bool = false
}

/// What a modifier does: what it applies to and how it selects targets.
///
/// In JSONL the field is called `func`; it is absent from `SDESchema.swift` because the generator
/// skips Swift keywords.
public enum ModifierFunction: UInt8, Sendable, Hashable, SQLiteValue {
    case itemModifier = 0
    case locationModifier = 1
    case locationGroupModifier = 2
    case locationRequiredSkillModifier = 3
    case ownerRequiredSkillModifier = 4
    case effectStopper = 5
}

@Table("dogmaEffectModifiers")
public struct DogmaEffectModifier {
    @PrimaryKey public var effectID: EffectID
    @PrimaryKey public var index: Int
    public var function: ModifierFunction
    public var domain: String = ""
    public var modifiedAttributeID: AttributeID? = nil
    public var modifyingAttributeID: AttributeID? = nil
    /// `operation` can be `-1` and is absent for `EffectStopper`, hence signed and optional.
    public var operation: Int? = nil
    public var groupID: GroupID? = nil
    public var skillTypeID: TypeID? = nil
    /// The effect that `EffectStopper` stops.
    public var stoppedEffectID: EffectID? = nil
}

// MARK: - Warfare buffs

@Table("dbuffCollections")
public struct DbuffCollectionInfo: Identifiable {
    @PrimaryKey public var id: WarfareBuffID
    public var displayNameID: NameID? = nil
    public var developerDescription: String = ""
    public var aggregateMode: String = ""
    public var operationName: String = ""
    public var showOutputValueInUI: String = ""
}

@Table("dbuffItemModifiers")
public struct DbuffItemModifier {
    @PrimaryKey public var buffID: WarfareBuffID
    @PrimaryKey public var attributeID: AttributeID
}

@Table("dbuffLocationModifiers")
public struct DbuffLocationModifier {
    @PrimaryKey public var buffID: WarfareBuffID
    @PrimaryKey public var attributeID: AttributeID
}

@Table("dbuffLocationGroupModifiers")
public struct DbuffLocationGroupModifier {
    @PrimaryKey public var buffID: WarfareBuffID
    @PrimaryKey public var attributeID: AttributeID
    @PrimaryKey public var groupID: GroupID
}

@Table("dbuffLocationRequiredSkillModifiers")
public struct DbuffLocationRequiredSkillModifier {
    @PrimaryKey public var buffID: WarfareBuffID
    @PrimaryKey public var attributeID: AttributeID
    @PrimaryKey public var skillID: TypeID
}

// MARK: - Derived fitting tables
//
// Computed by the importer to match `Entity+Module.init` from DogmaKit.

/// Where an item is fitted or worn; one filter on one column for both slot and kind.
public enum DogmaItemKind: UInt8, Sendable, Hashable, CaseIterable, SQLiteValue {
    case none = 0
    case hi
    case med
    case low
    case rig
    case subsystem
    /// T3D tactical mode; recognized by group 1306 "Ship Modifiers".
    case mode
    case charge
    case drone
    case fighter
    case implant
    case booster
    case ship
    case structure
    case service
    case structureFighter
    case structureRig
    /// System environment effect: wormhole and incursion beacons, abyssal weather, pylons.
    case environment
    /// Planet type.
    case planet
    /// Colony structure.
    case planetaryFacility
    /// Everything else.
    case cargo
}

/// Hardpoint a module occupies.
public enum DogmaHardpoint: UInt8, Sendable, Hashable, SQLiteValue {
    case none = 0
    case turret
    case launcher
}

/// Item as the fitting UI sees it.
///
/// A separate table: fitting needs a small part of the catalog. Numbers are base values from
/// `typeAttributes`, without skills, subsystems and hull bonuses; real values come from DogmaKit.
@Table("dogmaItems")
public struct DogmaItem: Identifiable {
    @PrimaryKey @Index("dogmaItems_byRestricted") public var id: TypeID
    @Index public var kind: DogmaItemKind
    public var hardpoint: DogmaHardpoint = .none
    public var cpu: Double? = nil
    public var power: Double? = nil
    public var capacitorNeed: Double? = nil
    /// `upgradeCost` — the calibration a rig takes.
    public var calibration: Double? = nil
    public var droneBandwidthUsed: Double? = nil
    public var volume: Double? = nil
    /// Charge or module size; rig size is `rigSize`.
    public var chargeSize: UInt8? = nil
    public var rigSize: UInt8? = nil
    public var maxGroupFitted: Int? = nil
    public var maxGroupActive: Int? = nil
    public var metaGroupID: MetaGroupID? = nil
    public var metaLevel: Int? = nil
    public var techLevel: Int? = nil
    /// Whether the item has ship restrictions; a fast path past two `EXISTS`. The index is partial,
    /// on the raised flag.
    @IndexFilter("dogmaItems_byRestricted", .isTrue) public var hasShipRestrictions: Bool = false
}

/// Hull as the fitting UI sees it: slots and budgets. Base values; T3C slots depend on subsystems,
/// hence zero.
@Table("dogmaShips")
public struct DogmaShip: Identifiable {
    @PrimaryKey public var id: TypeID
    public var hiSlots: Int = 0
    public var medSlots: Int = 0
    public var lowSlots: Int = 0
    public var rigSlots: Int = 0
    public var subsystemSlots: Int = 0
    public var serviceSlots: Int = 0
    public var turretHardpoints: Int = 0
    public var launcherHardpoints: Int = 0
    public var cpuOutput: Double = 0
    public var powerOutput: Double = 0
    /// `upgradeCapacity` — the hull's calibration.
    public var calibration: Double = 0
    public var droneCapacity: Double = 0
    public var droneBandwidth: Double = 0
    public var rigSize: UInt8? = nil
    public var shieldCapacity: Double = 0
    public var armorHP: Double = 0
    public var structureHP: Double = 0
    public var capacitorCapacity: Double = 0
    public var maxVelocity: Double = 0
    /// Whether the hull has tactical modes (T3D); derived from types of group 1306.
    public var hasTacticalModes: Bool = false
}

/// Module ship restrictions — from `canFitShipType1…12` and `fitsToShipType`.
///
/// No rows means "fits everyone".
@Table("dogmaItemShipTypes")
public struct DogmaItemShipType {
    @PrimaryKey public var itemID: TypeID
    @PrimaryKey @Index public var shipTypeID: TypeID
}

/// The same by ship group — `canFitShipGroup01…20`.
@Table("dogmaItemShipGroups")
public struct DogmaItemShipGroup {
    @PrimaryKey public var itemID: TypeID
    @PrimaryKey @Index public var shipGroupID: GroupID
}

/// Charges a module accepts — `chargeGroup1…5`.
@Table("dogmaItemChargeGroups")
public struct DogmaItemChargeGroup {
    @PrimaryKey public var itemID: TypeID
    @PrimaryKey @Index public var chargeGroupID: GroupID
}

/// Skill requirements — `requiredSkill1…6` and their levels. The key is the skill, not the index.
@Table("dogmaItemSkills")
public struct DogmaItemSkill {
    @PrimaryKey public var itemID: TypeID
    @PrimaryKey @Index public var skillID: TypeID
    public var level: Int = 0
}
