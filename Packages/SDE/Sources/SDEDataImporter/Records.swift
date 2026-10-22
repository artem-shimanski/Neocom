//
//  Records.swift
//  SDE
//
//  Created by Artem Shimanski on 05.09.2026.
//

import SDEModels

/// Eight language fields as they appear in JSONL.
///
/// Needed where the generated schema does not fit (see `EffectRecord`).
struct RawLocalizedText: Decodable, Localizable {
    var de: String?
    var en: String = ""
    var es: String?
    var fr: String?
    var ja: String?
    var ko: String?
    var ru: String?
    var zh: String?

    var localized: Localized {
        Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh)
    }
}

/// `dogmaEffects.jsonl` with its own decoder.
///
/// The schema generator skips the `func` field (modifier kind) as a Swift keyword, and without it
/// the modifier table is meaningless.
struct EffectRecord: Decodable {
    struct Modifier: Decodable {
        var function: String = ""
        var domain: String = ""
        var modifiedAttributeID: Int?
        var modifyingAttributeID: Int?
        var operation: Int?
        var groupID: Int?
        var skillTypeID: Int?
        /// The effect that `EffectStopper` stops.
        var effectID: Int?

        enum CodingKeys: String, CodingKey {
            case function = "func"
            case domain, modifiedAttributeID, modifyingAttributeID, operation, groupID
            case skillTypeID, effectID
        }
    }

    var _key: Int = 0
    var name: String = ""
    var displayName: RawLocalizedText?
    var description: RawLocalizedText?
    var effectCategoryID: Int = 0
    var iconID: Int?
    var guid: String?
    var dischargeAttributeID: Int?
    var durationAttributeID: Int?
    var falloffAttributeID: Int?
    var rangeAttributeID: Int?
    var trackingSpeedAttributeID: Int?
    var resistanceAttributeID: Int?
    var fittingUsageChanceAttributeID: Int?
    var npcActivationChanceAttributeID: Int?
    var npcUsageChanceAttributeID: Int?
    var distribution: Int?
    var disallowAutoRepeat: Bool = false
    var electronicChance: Bool = false
    var isAssistance: Bool = false
    var isOffensive: Bool = false
    var isWarpSafe: Bool = false
    var propulsionChance: Bool = false
    var rangeChance: Bool = false
    var published: Bool = false
    var modifierInfo: [Modifier]?
}

extension ModifierFunction {
    /// Names as in SDE. An unknown value is a new CCP modifier kind; it must not be skipped.
    init?(sdeName: String) {
        switch sdeName {
        case "ItemModifier": self = .itemModifier
        case "LocationModifier": self = .locationModifier
        case "LocationGroupModifier": self = .locationGroupModifier
        case "LocationRequiredSkillModifier": self = .locationRequiredSkillModifier
        case "OwnerRequiredSkillModifier": self = .ownerRequiredSkillModifier
        case "EffectStopper": self = .effectStopper
        default: return nil
        }
    }
}

/// Dogma of one type, fully loaded into memory.
///
/// `typeDogma.jsonl` (26 MB) is not streamed: effects, restrictions and the presence of a record
/// are needed before the database's contents are known.
struct DogmaRecord {
    var attributes: [(id: AttributeID, value: Double)] = []
    var effects: [(id: EffectID, isDefault: Bool)] = []

    func value(_ id: AttributeID?) -> Double? {
        guard let id else { return nil }
        return attributes.first { $0.id == id }?.value
    }

    func has(_ id: EffectID?) -> Bool {
        guard let id else { return false }
        return effects.contains { $0.id == id }
    }
}

/// Attributes and effects the importer looks up by name.
///
/// A name missing from the dump is a build error, not `nil`.
struct DogmaNames {
    var attributes: [String: AttributeID] = [:]
    var effects: [String: EffectID] = [:]

    subscript(attribute name: String) -> AttributeID? { attributes[name] }
    subscript(effect name: String) -> EffectID? { effects[name] }

    /// All attributes whose name starts with the prefix, in numeric order.
    func attributes(prefix: String, excludingSuffix suffix: String? = nil) -> [AttributeID] {
        attributes
            .filter { entry in
                entry.key.hasPrefix(prefix) && !(suffix.map { entry.key.hasSuffix($0) } ?? false)
            }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.value)
    }

    /// "Skill — level" pairs: `requiredSkill1` + `requiredSkill1Level`.
    func requiredSkills() -> [(skill: AttributeID, level: AttributeID)] {
        (1...6).compactMap { index in
            guard let skill = attributes["requiredSkill\(index)"],
                  let level = attributes["requiredSkill\(index)Level"]
            else { return nil }
            return (skill, level)
        }
    }
}
