//
//  SkillCatalog.swift
//  TrainingKit
//

import SDEKit

/// In-memory reference of skills and implant bonuses; every operation is a dictionary lookup.
public struct SkillCatalog: Sendable {
    /// A skill as the training math sees it: rank, training attributes and prerequisites.
    public struct Skill: Sendable, Hashable {
        /// `skillTimeConstant`: the skill point multiplier, 1...16.
        public var rank: Double
        public var primaryAttribute: CharacterAttribute
        public var secondaryAttribute: CharacterAttribute
        public var prerequisites: [Requirement]

        public init(rank: Double,
                    primaryAttribute: CharacterAttribute,
                    secondaryAttribute: CharacterAttribute,
                    prerequisites: [Requirement] = []) {
            self.rank = rank
            self.primaryAttribute = primaryAttribute
            self.secondaryAttribute = secondaryAttribute
            self.prerequisites = prerequisites
        }
    }

    /// A skill at a level: the unit of prerequisites and training queues.
    public struct Requirement: Sendable, Hashable {
        public var skillID: TypeID
        public var level: Int

        public init(skillID: TypeID, level: Int) {
            self.skillID = skillID
            self.level = level
        }
    }

    public let skills: [TypeID: Skill]

    /// What each implant type gives to the character's attributes.
    ///
    /// One type can carry bonuses to several attributes (category 20 also holds boosters).
    public let implantBonuses: [TypeID: CharacterAttributes]

    public init(skills: [TypeID: Skill], implantBonuses: [TypeID: CharacterAttributes]) {
        self.skills = skills
        self.implantBonuses = implantBonuses
    }

    public subscript(_ id: TypeID) -> Skill? { skills[id] }

    public func isSkill(_ id: TypeID) -> Bool { skills[id] != nil }

    /// Sum of the bonuses of the given implants, attribute by attribute.
    public func attributes(ofImplants implants: [TypeID]) -> CharacterAttributes {
        implants.reduce(CharacterAttributes.zero) { total, implant in
            guard let bonus = implantBonuses[implant] else { return total }
            return total + bonus
        }
    }

    /// Depth-first expansion of the requirements, prerequisites first, duplicates collapsed to
    /// the highest level.
    ///
    /// Types missing from the catalog are kept without prerequisites; see `isSkill(_:)`.
    /// Cyclic data does not recurse forever: each skill appears once, but the order inside
    /// a cycle is unspecified.
    public func expand(_ requirements: [Requirement]) -> [Requirement] {
        var levels: [TypeID: Int] = [:]
        var order: [TypeID] = []
        var visited: Set<TypeID> = []

        func visit(_ requirement: Requirement) {
            let id = requirement.skillID
            levels[id] = max(levels[id] ?? Int.min, requirement.level)
            // Prerequisites do not depend on the level, so a repeat visit only raises it.
            guard visited.insert(id).inserted else { return }
            for prerequisite in self[id]?.prerequisites ?? [] {
                visit(prerequisite)
            }
            order.append(id)
        }

        for requirement in requirements {
            visit(requirement)
        }

        return order.map { Requirement(skillID: $0, level: levels[$0] ?? 0) }
    }
}
