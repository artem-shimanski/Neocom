//
//  Character.swift
//  SDE
//
//  Created by Artem Shimanski on 04.09.2026.
//

import LiteRow

@Table("races")
public struct RaceInfo: Identifiable {
    @PrimaryKey public var id: RaceID
    public var nameID: NameID
    public var descriptionID: DescriptionID? = nil
    public var iconID: IconID? = nil
    public var shipTypeID: TypeID? = nil
}

/// Starting skills of a race. The key is the skill: JSON order is not significant.
@Table("raceSkills")
public struct RaceSkill {
    @PrimaryKey public var raceID: RaceID
    @PrimaryKey public var skillID: TypeID
    public var level: Int = 0
}

@Table("bloodlines")
public struct BloodlineInfo: Identifiable {
    @PrimaryKey public var id: BloodlineID
    public var nameID: NameID
    public var descriptionID: DescriptionID? = nil
    public var iconID: IconID? = nil
    public var raceID: RaceID
    public var corporationID: CorporationID
    public var charisma: Int = 0
    public var intelligence: Int = 0
    public var memory: Int = 0
    public var perception: Int = 0
    public var willpower: Int = 0
}

@Table("ancestries")
public struct AncestryInfo: Identifiable {
    @PrimaryKey public var id: AncestryID
    public var nameID: NameID
    public var descriptionID: DescriptionID? = nil
    /// Ancestry `shortDescription` is not localized in SDE.
    public var shortDescription: String? = nil
    public var iconID: IconID? = nil
    public var bloodlineID: BloodlineID
    public var charisma: Int = 0
    public var intelligence: Int = 0
    public var memory: Int = 0
    public var perception: Int = 0
    public var willpower: Int = 0
}

/// Character attributes (perception, memory, …). Only the name is localized.
@Table("characterAttributes")
public struct CharacterAttributeInfo: Identifiable {
    @PrimaryKey public var id: CharacterAttributeID
    public var nameID: NameID
    public var iconID: IconID? = nil
    public var description: String = ""
    public var shortDescription: String = ""
    public var notes: String = ""
}

/// Character attribute as a value, not a dogma attribute number (164…168); the importer resolves
/// the number by name.
public enum CharacterAttribute: UInt8, Sendable, Hashable, CaseIterable, SQLiteValue {
    case charisma = 164
    case intelligence = 165
    case memory = 166
    case perception = 167
    case willpower = 168
}

/// Jump clone class.
@Table("cloneGrades")
public struct CloneGradeInfo: Identifiable {
    @PrimaryKey public var id: CloneGradeID
    public var name: String = ""
}

@Table("cloneGradeSkills")
public struct CloneGradeSkill {
    @PrimaryKey public var cloneGradeID: CloneGradeID
    @PrimaryKey public var skillID: TypeID
    public var level: Int = 0
}

// MARK: - Certificates and mastery

@Table("certificates")
public struct CertificateInfo: Identifiable {
    @PrimaryKey public var id: CertificateID
    public var nameID: NameID
    public var descriptionID: DescriptionID? = nil
    public var groupID: GroupID
}

/// Skill included in a certificate and the level needed at each tier (five columns).
@Table("certificateSkills")
public struct CertificateSkill {
    @PrimaryKey public var certificateID: CertificateID
    @PrimaryKey public var skillID: TypeID
    public var basic: Int = 0
    public var standard: Int = 0
    public var improved: Int = 0
    public var advanced: Int = 0
    public var elite: Int = 0
}

/// Types the certificate is recommended for.
@Table("certificateRecommendations")
public struct CertificateRecommendation {
    @PrimaryKey public var certificateID: CertificateID
    @PrimaryKey @Index public var typeID: TypeID
}

/// Mastery: which certificates a ship needs at each level.
///
/// `masteries.jsonl` is keyed by type, the nested `_key` is the mastery level (0…4).
@Table("typeMasteries")
public struct TypeMastery {
    @PrimaryKey public var typeID: TypeID
    @PrimaryKey public var level: Int
    @PrimaryKey public var certificateID: CertificateID
}

/// Skill as the training-time calculation sees it.
///
/// Derived table: the values live in `typeAttributes` — `skillTimeConstant` (275),
/// `primaryAttribute` (180), `secondaryAttribute` (181).
@Table("dogmaSkills")
public struct DogmaSkill: Identifiable {
    @PrimaryKey public var id: TypeID
    /// `skillTimeConstant`: skill size multiplier, 1…16.
    public var rank: Double = 1
    public var primaryAttribute: CharacterAttribute
    public var secondaryAttribute: CharacterAttribute
}

/// What an implant gives character attributes.
///
/// Only non-zero bonuses `charismaBonus`…`willpowerBonus` (175…179). The key is the attribute.
@Table("dogmaImplantAttributes")
public struct DogmaImplantAttribute {
    @PrimaryKey public var implantID: TypeID
    @PrimaryKey public var attribute: CharacterAttribute
    public var bonus: Int = 0
}
