//
//  TrainingQueue.swift
//  TrainingKit
//

import Foundation
import SDEKit

/// A training plan: the levels the character has yet to train, in trainable order, each with
/// its training time. The only place where plan training time is computed.
public struct TrainingQueue: Sendable {
    /// One level of one skill.
    public struct Item: Sendable, Hashable, Identifiable {
        public var skillID: TypeID
        public var targetLevel: Int
        public var startSkillPoints: Int
        public var finishSkillPoints: Int
        public var trainingTime: TimeInterval
        /// The attributes the skill trains on, for timing against other attributes
        /// (`AttributeRemap`).
        public var primaryAttribute: CharacterAttribute
        public var secondaryAttribute: CharacterAttribute
        /// The points the level still needs; what `trainingTime` was computed from.
        public var skillPoints: Int { max(finishSkillPoints - startSkillPoints, 0) }
        /// The pair (skill, level).
        public var id: some Hashable { [skillID.rawValue, UInt32(targetLevel)] }

        public init(skillID: TypeID,
                    targetLevel: Int,
                    startSkillPoints: Int,
                    finishSkillPoints: Int,
                    trainingTime: TimeInterval,
                    primaryAttribute: CharacterAttribute,
                    secondaryAttribute: CharacterAttribute) {
            self.skillID = skillID
            self.targetLevel = targetLevel
            self.startSkillPoints = startSkillPoints
            self.finishSkillPoints = finishSkillPoints
            self.trainingTime = trainingTime
            self.primaryAttribute = primaryAttribute
            self.secondaryAttribute = secondaryAttribute
        }
    }

    private let pilot: Pilot
    private let catalog: SkillCatalog

    public init(pilot: Pilot, catalog: SkillCatalog) {
        self.pilot = pilot
        self.catalog = catalog
    }

    /// The pilot's attributes without implants, and the implants' share.
    public var baseAttributes: CharacterAttributes { pilot.baseAttributes }
    public var implantBonus: CharacterAttributes { pilot.implantBonus }

    public private(set) var items: [Item] = []

    public var totalTime: TimeInterval { items.reduce(0) { $0 + $1.trainingTime } }
    public var isEmpty: Bool { items.isEmpty }

    /// The skill up to `level`, with every prerequisite the character is missing.
    public mutating func add(skill: TypeID, level: Int) {
        add(requirements: [SkillCatalog.Requirement(skillID: skill, level: level)])
    }

    /// The requirements with all their prerequisites the character is missing.
    ///
    /// The list is expanded in one call, so a skill asked for at two levels is queued once, at
    /// the higher one.
    public mutating func add(requirements: [SkillCatalog.Requirement]) {
        for requirement in catalog.expand(requirements) {
            // The expansion passes unknown types through; without a rank there is no time to show.
            guard let skill = catalog[requirement.skillID] else { continue }
            append(requirement.skillID, skill: skill, upTo: requirement.level)
        }
    }

    /// Removes the level and everything above it in the same skill.
    ///
    /// Levels train in order, so higher levels cannot stay.
    public mutating func remove(_ item: Item) {
        items.removeAll { $0.skillID == item.skillID && $0.targetLevel >= item.targetLevel }
    }

    /// Time of the whole level, or `nil` when it is not in the queue.
    public func time(forSkill skill: TypeID, level: Int) -> TimeInterval? {
        item(skill, level)?.trainingTime
    }

    // MARK: - Building

    private func item(_ skill: TypeID, _ level: Int) -> Item? {
        items.first { $0.skillID == skill && $0.targetLevel == level }
    }

    /// Appends the missing levels of one skill, lowest first.
    private mutating func append(_ skillID: TypeID, skill: SkillCatalog.Skill, upTo level: Int) {
        let first = max(pilot.trainedLevel(of: skillID) + 1, 1)
        guard first <= level else { return }

        for targetLevel in first...level {
            guard item(skillID, targetLevel) == nil else { continue }

            let finishSkillPoints = TrainingMath.skillPoints(rank: skill.rank, level: targetLevel)
            // Follows a planned level, or is the skill's first and starts at the character's
            // own points.
            let startSkillPoints = item(skillID, targetLevel - 1)?.finishSkillPoints
                ?? max(pilot.skillPoints(in: skillID),
                       TrainingMath.skillPoints(rank: skill.rank, level: targetLevel - 1))

            // A skill can hold more points than the level requires.
            let points = max(finishSkillPoints - startSkillPoints, 0)
            let time = TrainingMath.trainingTime(
                skillPoints: points,
                primary: pilot.attributes[skill.primaryAttribute],
                secondary: pilot.attributes[skill.secondaryAttribute]
            )

            items.append(Item(skillID: skillID,
                              targetLevel: targetLevel,
                              startSkillPoints: startSkillPoints,
                              finishSkillPoints: finishSkillPoints,
                              trainingTime: time,
                              primaryAttribute: skill.primaryAttribute,
                              secondaryAttribute: skill.secondaryAttribute))
        }
    }
}
