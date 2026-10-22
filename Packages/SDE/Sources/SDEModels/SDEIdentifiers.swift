//
//  SDEIdentifiers.swift
//  SDE
//
//  Created by Artem Shimanski on 01.09.2026.
//

import LiteRow

// `rawValue` width is chosen by the maximum `_key` in the dump (SDE 3284752, values next to the
// types): decoding goes through `Self(exactly:)`, and a narrow type gives `integerOutOfRange`.
//
// Files keyed by type (`typeDogma`, `typeMaterials`, `typeBonus`, `masteries`, `blueprints`,
// `dynamicItemAttributes`, `controlTowerResources`, `compressibleTypes`) have no ID of their own:
// the key is a `TypeID` (up to 371027).

extension TypeID: @retroactive SQLiteValue {}
extension GroupID: @retroactive SQLiteValue {}
extension CategoryID: @retroactive SQLiteValue {}
extension AttributeID: @retroactive SQLiteValue {}
extension AttributeCategoryID: @retroactive SQLiteValue {}
extension UnitID: @retroactive SQLiteValue {}
extension EffectID: @retroactive SQLiteValue {}
extension MetaGroupID: @retroactive SQLiteValue {}
extension SchematicID: @retroactive SQLiteValue {}
extension WarfareBuffID: @retroactive SQLiteValue {}

// `GroupID` and `CategoryID` from DogmaIDs are `UInt16`: the only category beyond it is 350001
// (Infantry), and all 17 groups with ID > 65535 belong to it. It has no published types.

/// String shown to the user: the name of a type, group or market group.
///
/// The text lives in the language file (`names`); without a translation it is the English string. A
/// language file is valid only for its own build (`meta.buildNumber`).
public struct NameID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt32
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// Long text: type description, bonus text, attribute hint. A separate space and table from
/// `NameID`; not in the search index.
public struct DescriptionID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt32
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 27414
public struct IconID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt16
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 3851
public struct MarketGroupID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt16
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 168
public struct RaceID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt16
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 27
public struct BloodlineID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt16
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 64
public struct AncestryID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt16
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 5
public struct CharacterAttributeID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt16
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 8
public struct CloneGradeID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt16
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 2269
public struct CertificateID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt16
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 500029 does not fit in `UInt16`: faction IDs are from the owner range (500000+).
public struct FactionID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt32
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// NPC corporations are in the owner range (1000000+).
public struct CorporationID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt32
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 121
public struct StationOperationID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt16
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 27
public struct StationServiceID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt16
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 20
public struct CorporationActivityID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt16
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

// Region, constellation and system IDs are in the ranges 10000000+, 20000000+ and 30000000+
// (wormholes and abyss higher), hence `UInt32`.

/// max 19000001
public struct RegionID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt32
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 26000001
public struct ConstellationID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt32
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}

/// max 36000001
public struct SolarSystemID: SDEIdentifier, SQLiteValue {
    public var rawValue: UInt32
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public init(integerLiteral value: RawValue) { self.rawValue = value }
}
