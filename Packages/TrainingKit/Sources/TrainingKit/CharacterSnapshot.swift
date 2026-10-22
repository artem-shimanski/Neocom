//
//  CharacterSnapshot.swift
//  TrainingKit
//

import Foundation
import SDEKit

/// Character data as ESI returns it, without the ESI types; `Codable` for the disk cache.
public struct CharacterSnapshot: Codable, Sendable, Hashable {
    public struct SkillRecord: Codable, Sendable, Hashable {
        public var skillID: TypeID
        public var trainedLevel: Int
        /// Differs from `trainedLevel` for alpha clones.
        public var activeLevel: Int
        public var skillPoints: Int

        public init(skillID: TypeID, trainedLevel: Int, activeLevel: Int, skillPoints: Int) {
            self.skillID = skillID
            self.trainedLevel = trainedLevel
            self.activeLevel = activeLevel
            self.skillPoints = skillPoints
        }
    }

    public struct QueueEntry: Codable, Sendable, Hashable {
        public var skillID: TypeID
        public var finishedLevel: Int
        public var position: Int
        public var startDate: Date?
        public var finishDate: Date?
        public var levelStartSkillPoints: Int?
        public var levelEndSkillPoints: Int?

        public init(skillID: TypeID, finishedLevel: Int, position: Int,
                    startDate: Date? = nil, finishDate: Date? = nil,
                    levelStartSkillPoints: Int? = nil, levelEndSkillPoints: Int? = nil) {
            self.skillID = skillID
            self.finishedLevel = finishedLevel
            self.position = position
            self.startDate = startDate
            self.finishDate = finishDate
            self.levelStartSkillPoints = levelStartSkillPoints
            self.levelEndSkillPoints = levelEndSkillPoints
        }
    }

    public var attributes: CharacterAttributes   // base, without implants
    public var implants: [TypeID]
    public var skills: [SkillRecord]
    public var queue: [QueueEntry]
    public var totalSkillPoints: Int64
    public var unallocatedSkillPoints: Int64?

    // The three fields below come from `/attributes` and are not used by the training math.

    /// Remaps the character has banked and can spend at will.
    public var bonusRemaps: Int?
    /// When the character last remapped their attributes.
    public var lastRemapDate: Date?
    /// When the next free remap accrues, as ESI computes it.
    public var accruedRemapCooldownDate: Date?

    public init(attributes: CharacterAttributes, implants: [TypeID], skills: [SkillRecord],
                queue: [QueueEntry], totalSkillPoints: Int64,
                unallocatedSkillPoints: Int64? = nil,
                bonusRemaps: Int? = nil,
                lastRemapDate: Date? = nil,
                accruedRemapCooldownDate: Date? = nil) {
        self.attributes = attributes
        self.implants = implants
        self.skills = skills
        self.queue = queue
        self.totalSkillPoints = totalSkillPoints
        self.unallocatedSkillPoints = unallocatedSkillPoints
        self.bonusRemaps = bonusRemaps
        self.lastRemapDate = lastRemapDate
        self.accruedRemapCooldownDate = accruedRemapCooldownDate
    }
}
