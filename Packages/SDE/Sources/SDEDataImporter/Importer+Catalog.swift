//
//  Importer+Catalog.swift
//  SDE
//
//  Created by Artem Shimanski on 05.09.2026.
//

import Foundation
import LiteRow
import LiteRowBuild
import SDEModels

extension Importer {

    // MARK: - Ship bonuses

    func importTraits() throws {
        var rows: [TypeTrait] = []
        try JSONL.forEach(TypeBonusInfo.self, at: url("typeBonus")) { raw in
            let typeID = TypeID(rawValue: UInt32(raw._key))
            guard self.keptTypes[typeID] != nil else { return }

            for (index, bonus) in (raw.roleBonuses ?? []).enumerated() {
                rows.append(TypeTrait(
                    typeID: typeID, kind: .role, skillID: 0, index: index,
                    textID: self.textBuilder.description(bonus.bonusText.localized),
                    bonus: bonus.bonus,
                    unitID: bonus.unitID.map { UnitID(rawValue: UInt16($0)) },
                    importance: bonus.importance
                ))
            }
            for (index, bonus) in (raw.miscBonuses ?? []).enumerated() {
                rows.append(TypeTrait(
                    typeID: typeID, kind: .misc, skillID: 0, index: index,
                    textID: self.textBuilder.description(bonus.bonusText.localized),
                    bonus: bonus.bonus,
                    unitID: bonus.unitID.map { UnitID(rawValue: UInt16($0)) },
                    importance: bonus.importance,
                    isPositive: bonus.isPositive
                ))
            }
            for skill in raw.types ?? [] {
                let skillID = TypeID(rawValue: UInt32(skill._key))
                for (index, bonus) in skill._value.enumerated() {
                    rows.append(TypeTrait(
                        typeID: typeID, kind: .skill, skillID: skillID, index: index,
                        textID: self.textBuilder.description(bonus.bonusText.localized),
                        bonus: bonus.bonus,
                        unitID: bonus.unitID.map { UnitID(rawValue: UInt16($0)) },
                        importance: bonus.importance
                    ))
                }
            }
        }
        try main.create(TypeTrait.self, filledWith: rows, options: .keyOrdered)
    }

    // MARK: - Reprocessing

    func importMaterials() throws {
        var materials: [TypeMaterial] = []
        var random: [TypeRandomMaterial] = []
        try JSONL.forEach(TypeMaterialInfo.self, at: url("typeMaterials")) { raw in
            let typeID = TypeID(rawValue: UInt32(raw._key))
            guard self.keptTypes[typeID] != nil else { return }
            for material in raw.materials ?? [] {
                materials.append(TypeMaterial(
                    typeID: typeID,
                    materialTypeID: TypeID(rawValue: UInt32(material.materialTypeID)),
                    quantity: material.quantity
                ))
            }
            for material in raw.randomizedMaterials ?? [] {
                random.append(TypeRandomMaterial(
                    typeID: typeID,
                    materialTypeID: TypeID(rawValue: UInt32(material.materialTypeID)),
                    quantityMin: material.quantityMin,
                    quantityMax: material.quantityMax
                ))
            }
        }
        try main.create(TypeMaterial.self, filledWith: materials, options: .keyOrdered)
        try main.create(TypeRandomMaterial.self, filledWith: random, options: .keyOrdered)
    }

    // MARK: - Mutaplasmids

    func importMutaplasmids() throws {
        let raw = try JSONL.array(DynamicItemAttributeInfo.self, at: url("dynamicItemAttributes"))
        let kept = raw.filter { keptTypes[TypeID(rawValue: UInt32($0._key))] != nil }

        try main.create(DynamicItemAttributeRow.self, filledWith: kept.map {
            DynamicItemAttributeRow(id: TypeID(rawValue: UInt32($0._key)))
        })
        try main.create(DynamicItemAttributeRange.self, filledWith: kept.flatMap { raw in
            raw.attributeIDs.map {
                DynamicItemAttributeRange(
                    mutaplasmidID: TypeID(rawValue: UInt32(raw._key)),
                    attributeID: AttributeID(rawValue: UInt16($0._key)),
                    min: $0.min,
                    max: $0.max,
                    highIsGood: $0.highIsGood
                )
            }
        }, options: .keyOrdered)
        try main.create(DynamicItemAttributeMapping.self, filledWith: kept.flatMap { raw in
            raw.inputOutputMapping.flatMap { mapping in
                mapping.applicableTypes.map {
                    DynamicItemAttributeMapping(
                        mutaplasmidID: TypeID(rawValue: UInt32(raw._key)),
                        applicableTypeID: TypeID(rawValue: UInt32($0)),
                        resultingTypeID: TypeID(rawValue: UInt32(mapping.resultingType))
                    )
                }
            }
        }, options: .keyOrdered)
    }

    // MARK: - Character

    func importCharacter() throws {
        let races = try JSONL.array(RaceInfo.self, at: url("races"))
        try main.create(RaceRow.self, filledWith: races.compactMap { raw in
            guard let id = UInt16(exactly: raw._key).map(RaceID.init(rawValue:)) else { return nil }
            return RaceRow(
                id: id,
                nameID: textBuilder.name(raw.name.localized),
                descriptionID: textBuilder.description(raw.description?.localized),
                iconID: raw.iconID.flatMap { UInt16(exactly: $0).map(IconID.init(rawValue:)) },
                shipTypeID: raw.shipTypeID.map { TypeID(rawValue: UInt32($0)) }
            )
        })
        try main.create(RaceSkill.self, filledWith: races.flatMap { raw -> [RaceSkill] in
            guard let id = UInt16(exactly: raw._key).map(RaceID.init(rawValue:)) else { return [] }
            return (raw.skills ?? []).map {
                RaceSkill(raceID: id, skillID: TypeID(rawValue: UInt32($0._key)), level: $0._value)
            }
        }, options: .keyOrdered)

        let bloodlines = try JSONL.array(BloodlineInfo.self, at: url("bloodlines"))
        try main.create(BloodlineRow.self, filledWith: bloodlines.map { raw in
            BloodlineRow(
                id: BloodlineID(rawValue: UInt16(raw._key)),
                nameID: textBuilder.name(raw.name.localized),
                descriptionID: textBuilder.description(raw.description.localized),
                iconID: raw.iconID.flatMap { UInt16(exactly: $0).map(IconID.init(rawValue:)) },
                raceID: RaceID(rawValue: UInt16(raw.raceID)),
                corporationID: CorporationID(rawValue: UInt32(raw.corporationID)),
                charisma: raw.charisma,
                intelligence: raw.intelligence,
                memory: raw.memory,
                perception: raw.perception,
                willpower: raw.willpower
            )
        })

        let ancestries = try JSONL.array(AncestryInfo.self, at: url("ancestries"))
        try main.create(AncestryRow.self, filledWith: ancestries.map { raw in
            AncestryRow(
                id: AncestryID(rawValue: UInt16(raw._key)),
                nameID: textBuilder.name(raw.name.localized),
                descriptionID: textBuilder.description(raw.description.localized),
                shortDescription: raw.shortDescription,
                iconID: raw.iconID.flatMap { UInt16(exactly: $0).map(IconID.init(rawValue:)) },
                bloodlineID: BloodlineID(rawValue: UInt16(raw.bloodlineID)),
                charisma: raw.charisma,
                intelligence: raw.intelligence,
                memory: raw.memory,
                perception: raw.perception,
                willpower: raw.willpower
            )
        })

        let attributes = try JSONL.array(CharacterAttributeInfo.self, at: url("characterAttributes"))
        try main.create(CharacterAttributeRow.self, filledWith: attributes.map { raw in
            CharacterAttributeRow(
                id: CharacterAttributeID(rawValue: UInt16(raw._key)),
                nameID: textBuilder.name(raw.name.localized),
                iconID: UInt16(exactly: raw.iconID).map(IconID.init(rawValue:)),
                description: raw.description,
                shortDescription: raw.shortDescription,
                notes: raw.notes
            )
        })

        let clones = try JSONL.array(CloneGradeInfo.self, at: url("cloneGrades"))
        try main.create(CloneGradeRow.self, filledWith: clones.map {
            CloneGradeRow(id: CloneGradeID(rawValue: UInt16($0._key)), name: $0.name)
        })
        try main.create(CloneGradeSkill.self, filledWith: clones.flatMap { raw in
            raw.skills.map {
                CloneGradeSkill(cloneGradeID: CloneGradeID(rawValue: UInt16(raw._key)),
                                skillID: TypeID(rawValue: UInt32($0.typeID)),
                                level: $0.level)
            }
        }, options: .keyOrdered)
    }

    // MARK: - Certificates and mastery

    func importCertificates() throws {
        let certificates = try JSONL.array(CertificateInfo.self, at: url("certificates"))
        try main.create(CertificateRow.self, filledWith: certificates.compactMap { raw in
            guard let groupID = UInt16(exactly: raw.groupID).map(GroupID.init(rawValue:)) else { return nil }
            return CertificateRow(
                id: CertificateID(rawValue: UInt16(raw._key)),
                nameID: textBuilder.name(raw.name.localized),
                descriptionID: textBuilder.description(raw.description.localized),
                groupID: groupID
            )
        })
        try main.create(CertificateSkill.self, filledWith: certificates.flatMap { raw in
            raw.skillTypes.map {
                CertificateSkill(
                    certificateID: CertificateID(rawValue: UInt16(raw._key)),
                    skillID: TypeID(rawValue: UInt32($0._key)),
                    basic: $0.basic,
                    standard: $0.standard,
                    improved: $0.improved,
                    advanced: $0.advanced,
                    elite: $0.elite
                )
            }
        }, options: .keyOrdered)
        try main.create(CertificateRecommendation.self, filledWith: certificates.flatMap { raw in
            (raw.recommendedFor ?? []).compactMap { typeID -> CertificateRecommendation? in
                let id = TypeID(rawValue: UInt32(typeID))
                guard keptTypes[id]?.published == true else { return nil }
                return CertificateRecommendation(
                    certificateID: CertificateID(rawValue: UInt16(raw._key)),
                    typeID: id
                )
            }
        }, options: .keyOrdered)

        // `masteries.jsonl` is keyed by type, the nested `_key` is the mastery level, the values
        // are certificates.
        var masteries: [TypeMastery] = []
        try JSONL.forEach(MasteryInfo.self, at: url("masteries")) { raw in
            let typeID = TypeID(rawValue: UInt32(raw._key))
            guard self.keptTypes[typeID] != nil else { return }
            for level in raw._value {
                for certificate in level._value {
                    masteries.append(TypeMastery(
                        typeID: typeID,
                        level: level._key,
                        certificateID: CertificateID(rawValue: UInt16(certificate))
                    ))
                }
            }
        }
        try main.create(TypeMastery.self, filledWith: masteries, options: .keyOrdered)
    }
}
