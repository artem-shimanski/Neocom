//
//  Industry.swift
//  SDE
//
//  Created by Artem Shimanski on 04.09.2026.
//

import LiteRow

/// Kind of blueprint work. In SDE these are six named `activities` fields; the key is `(blueprint,
/// activity)`.
public enum BlueprintActivity: UInt8, Sendable, Hashable, CaseIterable, SQLiteValue {
    case manufacturing = 0
    case researchTime = 1
    case researchMaterial = 2
    case copying = 3
    case invention = 4
    case reaction = 5
}

/// Blueprint. The key is its own `TypeID`.
@Table("blueprints")
public struct BlueprintInfo: Identifiable {
    @PrimaryKey public var id: TypeID
    public var maxProductionLimit: Int = 0
}

@Table("blueprintActivities")
public struct BlueprintActivityInfo {
    @PrimaryKey public var blueprintID: TypeID
    @PrimaryKey public var activity: BlueprintActivity
    /// Seconds.
    public var time: Int = 0
}

@Table("blueprintMaterials")
public struct BlueprintMaterial {
    @PrimaryKey public var blueprintID: TypeID
    @PrimaryKey public var activity: BlueprintActivity
    @PrimaryKey public var materialTypeID: TypeID
    public var quantity: Int = 0
}

@Table("blueprintProducts")
public struct BlueprintProduct {
    @PrimaryKey public var blueprintID: TypeID
    @PrimaryKey public var activity: BlueprintActivity
    @PrimaryKey @Index public var productTypeID: TypeID
    public var quantity: Int = 0
    /// Filled only for invention.
    public var probability: Double? = nil
}

@Table("blueprintSkills")
public struct BlueprintSkill {
    @PrimaryKey public var blueprintID: TypeID
    @PrimaryKey public var activity: BlueprintActivity
    @PrimaryKey public var skillID: TypeID
    public var level: Int = 0
}

// MARK: - Planetary

/// Production schema on a planet.
@Table("planetSchematics")
public struct PlanetSchematicInfo: Identifiable {
    @PrimaryKey public var id: SchematicID
    public var nameID: NameID
    /// Seconds.
    public var cycleTime: Int = 0
}

/// Schema input and output; the type is in the JSON element's `_key`.
@Table("planetSchematicTypes")
public struct PlanetSchematicType {
    @PrimaryKey public var schematicID: SchematicID
    @PrimaryKey @Index public var typeID: TypeID
    public var isInput: Bool = false
    public var quantity: Int = 0
}

/// Structure types the schema runs on (`pins` in SDE).
@Table("planetSchematicFacilities")
public struct PlanetSchematicFacility {
    @PrimaryKey public var schematicID: SchematicID
    @PrimaryKey public var facilityTypeID: TypeID
}

// MARK: - Starbases and stations

/// Control tower fuel. The key is the tower's own `TypeID`.
@Table("controlTowerResources")
public struct ControlTowerResource {
    @PrimaryKey public var towerID: TypeID
    @PrimaryKey public var resourceTypeID: TypeID
    public var quantity: Int = 0
    public var purpose: Int = 0
    /// Restrictions under which the resource is required: faction tower fuel and the security
    /// status dependency.
    public var factionID: FactionID? = nil
    public var minSecurityLevel: Double? = nil
}

@Table("stationServices")
public struct StationServiceInfo: Identifiable {
    @PrimaryKey public var id: StationServiceID
    public var nameID: NameID
    public var descriptionID: DescriptionID? = nil
}

@Table("stationOperations")
public struct StationOperationInfo: Identifiable {
    @PrimaryKey public var id: StationOperationID
    public var nameID: NameID
    public var descriptionID: DescriptionID? = nil
    public var activityID: Int = 0
    public var border: Double = 0
    public var corridor: Double = 0
    public var fringe: Double = 0
    public var hub: Double = 0
    public var ratio: Double = 0
    public var manufacturingFactor: Double = 0
    public var researchFactor: Double = 0
}

@Table("stationOperationServices")
public struct StationOperationService {
    @PrimaryKey public var operationID: StationOperationID
    @PrimaryKey public var serviceID: StationServiceID
}

/// Station type for an operation per race; in JSON `_key` is the race, `_value` the station type.
@Table("stationOperationStationTypes")
public struct StationOperationStationType {
    @PrimaryKey public var operationID: StationOperationID
    @PrimaryKey public var raceID: RaceID
    public var stationTypeID: TypeID
}

@Table("corporationActivities")
public struct CorporationActivityInfo: Identifiable {
    @PrimaryKey public var id: CorporationActivityID
    public var nameID: NameID
}
