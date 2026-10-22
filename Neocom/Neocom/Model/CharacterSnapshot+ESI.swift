import ESIKit
import Foundation
import SDEKit
import TrainingKit

/// Builds a `CharacterSnapshot` from the four ESI responses that make it up.
///
/// The only conversion from the generated `Components.Schemas.*` types into the training domain.
extension CharacterSnapshot {
    init(attributes: Components.Schemas.CharactersCharacterIdAttributesGet,
         implants: [Int64],
         skills: Components.Schemas.CharactersSkills,
         queue: [Components.Schemas.CharactersSkillqueueSkill]) {
        // Read before the local `attributes` below shadows the parameter of the same name.
        let bonusRemaps = attributes.bonusRemaps.map(Int.init)
        let lastRemapDate = attributes.lastRemapDate
        let accruedRemapCooldownDate = attributes.accruedRemapCooldownDate

        let attributes = CharacterAttributes(
            charisma: Int(attributes.charisma),
            intelligence: Int(attributes.intelligence),
            memory: Int(attributes.memory),
            perception: Int(attributes.perception),
            willpower: Int(attributes.willpower)
        )

        let implants = implants.compactMap { UInt32(exactly: $0) }.map { TypeID(rawValue: $0) }

        let skillRecords = skills.skills.compactMap { skill -> SkillRecord? in
            guard let rawValue = UInt32(exactly: skill.skillId) else { return nil }
            return SkillRecord(
                skillID: TypeID(rawValue: rawValue),
                trainedLevel: Int(skill.trainedSkillLevel),
                activeLevel: Int(skill.activeSkillLevel),
                skillPoints: Int(skill.skillpointsInSkill)
            )
        }

        let queueEntries = queue
            .sorted { $0.queuePosition < $1.queuePosition }
            .compactMap { entry -> QueueEntry? in
                guard let rawValue = UInt32(exactly: entry.skillId) else { return nil }
                return QueueEntry(
                    skillID: TypeID(rawValue: rawValue),
                    finishedLevel: Int(entry.finishedLevel),
                    position: Int(entry.queuePosition),
                    startDate: entry.startDate,
                    finishDate: entry.finishDate,
                    levelStartSkillPoints: entry.levelStartSp.map(Int.init),
                    levelEndSkillPoints: entry.levelEndSp.map(Int.init)
                )
            }

        self.init(
            attributes: attributes,
            implants: implants,
            skills: skillRecords,
            queue: queueEntries,
            totalSkillPoints: skills.totalSp,
            unallocatedSkillPoints: skills.unallocatedSp,
            bonusRemaps: bonusRemaps,
            lastRemapDate: lastRemapDate,
            accruedRemapCooldownDate: accruedRemapCooldownDate
        )
    }
}
