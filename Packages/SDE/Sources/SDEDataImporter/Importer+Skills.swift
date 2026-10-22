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
    ///
    /// Runs after `importFitting()`: it does not see skills (their `kind` is `.none`), so
    /// skill-to-skill requirements are appended to the `dogmaItemSkills` it created via
    /// `DatabaseBuilder.insert(_:)`.
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
        let requiredSkills = names.requiredSkills()

        var skillRows: [DogmaSkill] = []
        var implantRows: [DogmaImplantAttribute] = []
        var skillRequirementRows: [DogmaItemSkill] = []

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

                // Skill-to-skill requirements, as in `importFitting()`.
                for requirement in requiredSkills {
                    guard let skill = record.value(requirement.skill).flatMap({ UInt32(exactly: $0.rounded()) }),
                          skill != 0
                    else { continue }
                    skillRequirementRows.append(DogmaItemSkill(
                        itemID: id,
                        skillID: TypeID(rawValue: skill),
                        level: Int(record.value(requirement.level) ?? 1)
                    ))
                }
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
        try main.insert(skillRequirementRows)
    }
}
