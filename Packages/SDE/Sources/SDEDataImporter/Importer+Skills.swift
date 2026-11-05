//
//  Importer+Skills.swift
//  SDE
//
//  Created by Artem Shimanski on 17.09.2026.
//

import Foundation
import LiteRow
import LiteRowBuild
import SDEModels

extension Importer {

    /// Skills for training-time calculation and implant attribute bonuses.
    func importSkills() throws {
        let skillTimeConstant = try attribute("skillTimeConstant")
        let primaryAttribute = try attribute("primaryAttribute")
        let secondaryAttribute = try attribute("secondaryAttribute")
        let bonuses: [(attribute: AttributeID, target: CharacterAttribute)] = [
            (try attribute("charismaBonus"), .charisma),
            (try attribute("intelligenceBonus"), .intelligence),
            (try attribute("memoryBonus"), .memory),
            (try attribute("perceptionBonus"), .perception),
            (try attribute("willpowerBonus"), .willpower),
        ]

        var skillRows: [DogmaSkill] = []
        var implantRows: [DogmaImplantAttribute] = []

        for id in sortedTypes {
            let kept = keptTypes[id]!
            let record = dogma[id] ?? DogmaRecord()

            if kept.categoryID == Scope.skillCategory {
                // The default value would cause a division by zero in the training-time
                // calculation.
                guard let rank = record.value(skillTimeConstant) else {
                    throw ImportError.missing("skillTimeConstant у навыка \(id.rawValue)")
                }
                guard let primary = record.value(primaryAttribute)
                    .flatMap({ UInt8(exactly: $0.rounded()) })
                    .flatMap(CharacterAttribute.init(rawValue:))
                else {
                    throw ImportError.missing("primaryAttribute у навыка \(id.rawValue)")
                }
                guard let secondary = record.value(secondaryAttribute)
                    .flatMap({ UInt8(exactly: $0.rounded()) })
                    .flatMap(CharacterAttribute.init(rawValue:))
                else {
                    throw ImportError.missing("secondaryAttribute у навыка \(id.rawValue)")
                }
                skillRows.append(DogmaSkill(
                    id: id,
                    rank: rank,
                    primaryAttribute: primary,
                    secondaryAttribute: secondary
                ))
            }
            else if kept.categoryID == Scope.implantCategory {
                for (attribute, target) in bonuses {
                    guard let value = record.value(attribute), value != 0 else { continue }
                    implantRows.append(DogmaImplantAttribute(
                        implantID: id,
                        attribute: target,
                        bonus: Int(value.rounded())
                    ))
                }
            }
        }

        try main.create(DogmaSkill.self, filledWith: skillRows)
        try main.create(DogmaImplantAttribute.self, filledWith: implantRows, options: .keyOrdered)
    }

    /// Skill requirements of every type: modules, ships, skills, but also ores, POS modules and
    /// commodities.
    func importSkillRequirements() throws {
        let requiredSkills = names.requiredSkills()
        var rows: [DogmaItemSkill] = []

        for id in sortedTypes {
            guard let record = dogma[id] else { continue }
            for requirement in requiredSkills {
                guard let skill = record.value(requirement.skill).flatMap({ UInt32(exactly: $0.rounded()) }),
                      skill != 0
                else { continue }
                rows.append(DogmaItemSkill(
                    itemID: id,
                    skillID: TypeID(rawValue: skill),
                    level: Int(record.value(requirement.level) ?? 1)
                ))
            }
        }

        try main.create(DogmaItemSkill.self, filledWith: rows, options: .keyOrdered)
    }
}
