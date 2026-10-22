//
//  Types.swift
//  SDE
//
//  Created by Artem Shimanski on 23.08.2026.
//

import Foundation
import LiteRow
@_exported import DogmaIDs

/// Stamps that LiteRow checks when opening each file of the set.
///
/// `applicationID` tells whether the file is ours, `userVersion` whether the table layout matches;
/// both are the same in the main and language databases. They do not check that SDE builds match:
/// `SDEKit` does that by `meta.buildNumber`.
public enum SDESchema {
    /// `'SDE\0'`, so a debugger shows whose file it is.
    public static let applicationID: Int32 = 0x5344_4500
    /// Table layout. Bumped on any schema change that breaks reading.
    public static let version: Int32 = 1
}

/// Version of the dump the database was built from. One row.
@Table("meta")
public struct Meta: Identifiable {
    @PrimaryKey public var id: Int = 0
    public var buildNumber: Int
    public var releaseDate: String
}

@Table("categories")
public struct CategoryInfo: Identifiable {
    @PrimaryKey public var id: CategoryID
    public var nameID: NameID
    public var iconID: IconID? = nil
    public var published: Bool = false
}

@Table("groups")
public struct GroupInfo: Identifiable {
    @PrimaryKey public var id: GroupID
    @Index public var categoryID: CategoryID
    public var nameID: NameID
    public var iconID: IconID? = nil
    public var published: Bool = false
    public var anchorable: Bool = false
    public var anchored: Bool = false
    public var fittableNonSingleton: Bool = false
    public var useBasePrice: Bool = false
}

/// Item catalog. `nameID` is indexed for the join with the search index: fts5 returns a `rowid`
/// equal to `NameID`.
@Table("types")
public struct TypeInfo: Identifiable {
    @PrimaryKey public var id: TypeID
    @Index public var groupID: GroupID
    @Index public var nameID: NameID
    public var descriptionID: DescriptionID? = nil
    /// Partial: a minority of types have a market group.
    @Index(where: .notNull) public var marketGroupID: MarketGroupID? = nil
    public var metaGroupID: MetaGroupID? = nil
    public var metaLevel: Int? = nil
    /// Base type of a meta variant (T2, faction and abyssal versions refer to T1). The index is
    /// partial; the variant list is built from it.
    @Index(where: .notNull) public var variationParentID: TypeID? = nil
    public var raceID: RaceID? = nil
    public var factionID: FactionID? = nil
    public var iconID: IconID? = nil
    public var graphicID: Int? = nil
    public var soundID: Int? = nil
    public var basePrice: Double? = nil
    public var capacity: Double? = nil
    public var mass: Double? = nil
    public var radius: Double? = nil
    public var volume: Double? = nil
    public var portionSize: Int = 0
    public var published: Bool = false
}

@Table("metaGroups")
public struct MetaGroupInfo: Identifiable {
    @PrimaryKey public var id: MetaGroupID
    public var nameID: NameID
    public var descriptionID: DescriptionID? = nil
    public var iconID: IconID? = nil
    public var iconSuffix: String? = nil
    /// Meta group color for a badge; SDE has a nested `color` structure, here three columns.
    public var colorR: Double? = nil
    public var colorG: Double? = nil
    public var colorB: Double? = nil
}

/// Path to an image inside the client resources (`res:/ui/texture/...`); not human text.
@Table("icons")
public struct IconInfo: Identifiable {
    @PrimaryKey public var id: IconID
    public var iconFile: String = ""
}

/// PNG image of an icon. A separate table, to stay off pages with blobs.
///
/// Only market group icons (`marketGroups.iconID`) whose file is found in the icon directory; the
/// table is empty without a directory.
@Table("iconImages")
public struct IconImage: Identifiable {
    @PrimaryKey public var id: IconID
    public var png: Data
}

/// Compressed version of ore/ice/gas.
@Table("compressibleTypes")
public struct CompressibleTypeInfo: Identifiable {
    @PrimaryKey public var id: TypeID
    public var compressedTypeID: TypeID
}

// MARK: - Type dogma

/// Attribute value of a type. Raw dogma for the Attributes screen; the engine reads from its own
/// `sde.bin`, not from here.
@Table("typeAttributes")
public struct TypeAttribute {
    @PrimaryKey public var typeID: TypeID
    @PrimaryKey public var attributeID: AttributeID
    public var value: Double = 0
}

@Table("typeEffects")
public struct TypeEffect {
    @PrimaryKey public var typeID: TypeID
    @PrimaryKey public var effectID: EffectID
    public var isDefault: Bool = false
}

/// What a type is made of (reprocessing).
@Table("typeMaterials")
public struct TypeMaterial {
    @PrimaryKey public var typeID: TypeID
    @PrimaryKey public var materialTypeID: TypeID
    public var quantity: Int = 0
}

/// Materials with a random output; a separate list in SDE.
@Table("typeRandomMaterials")
public struct TypeRandomMaterial {
    @PrimaryKey public var typeID: TypeID
    @PrimaryKey public var materialTypeID: TypeID
    public var quantityMin: Int = 0
    public var quantityMax: Int = 0
}

// MARK: - Ship bonuses (traits)

/// Where a ship bonus comes from; determines the order and title of a section in the card.
public enum TraitKind: UInt8, Sendable, Hashable, SQLiteValue {
    /// Bonus per skill level; the skill is in `skillID`.
    case skill = 0
    /// Role bonus of the hull, independent of skills.
    case role = 1
    /// Other: what CCP put in `miscBonuses`.
    case misc = 2
}

/// Ship bonus description row (`typeBonus.jsonl`).
///
/// `skillID` = 0 for role and other bonuses, not `nil`: the column is part of the primary key.
@Table("typeTraits")
public struct TypeTrait {
    @PrimaryKey public var typeID: TypeID
    @PrimaryKey public var kind: TraitKind
    @PrimaryKey public var skillID: TypeID = 0
    @PrimaryKey public var index: Int
    public var textID: DescriptionID
    public var bonus: Double? = nil
    public var unitID: UnitID? = nil
    public var importance: Int = 0
    public var isPositive: Bool? = nil
}

// MARK: - Mutaplasmids

/// Mutaplasmid: the key is its own `TypeID`.
@Table("dynamicItemAttributes")
public struct DynamicItemAttributeInfo: Identifiable {
    @PrimaryKey public var id: TypeID
}

/// Bounds within which a mutaplasmid rolls an attribute.
@Table("dynamicItemAttributeRanges")
public struct DynamicItemAttributeRange {
    @PrimaryKey public var mutaplasmidID: TypeID
    @PrimaryKey public var attributeID: AttributeID
    public var min: Double = 0
    public var max: Double = 0
    /// Override of the "higher is better" direction for this attribute; `nil` means the attribute's
    /// own.
    public var highIsGood: Bool? = nil
}

/// What a module turns into: an "applicable type → result" pair.
@Table("dynamicItemAttributeMappings")
public struct DynamicItemAttributeMapping {
    @PrimaryKey public var mutaplasmidID: TypeID
    @PrimaryKey public var applicableTypeID: TypeID
    public var resultingTypeID: TypeID
}
