//
//  SkillCatalogTests.swift
//  TrainingKit
//

import Testing
import SDEKit
@testable import TrainingKit

@Suite("SkillCatalog")
struct SkillCatalogTests {
    // C requires B at level 3, B requires A at level 2, A requires nothing.
    private static let skillA = TypeID(rawValue: 1)
    private static let skillB = TypeID(rawValue: 2)
    private static let skillC = TypeID(rawValue: 3)

    private static let chain = SkillCatalog(
        skills: [
            skillA: .init(rank: 1, primaryAttribute: .memory, secondaryAttribute: .intelligence),
            skillB: .init(rank: 2, primaryAttribute: .memory, secondaryAttribute: .intelligence,
                          prerequisites: [.init(skillID: skillA, level: 2)]),
            skillC: .init(rank: 3, primaryAttribute: .perception, secondaryAttribute: .willpower,
                          prerequisites: [.init(skillID: skillB, level: 3)]),
        ],
        implantBonuses: [:]
    )

    // MARK: - Lookup

    @Test("subscript and isSkill answer for known and unknown types")
    func lookup() {
        #expect(Self.chain[Self.skillB]?.rank == 2)
        #expect(Self.chain[TypeID(rawValue: 999)] == nil)
        #expect(Self.chain.isSkill(Self.skillC))
        #expect(!Self.chain.isSkill(TypeID(rawValue: 999)))
    }

    // MARK: - expand

    @Test("expand returns prerequisites before the skill that needs them")
    func expandOrdersPrerequisitesFirst() {
        let result = Self.chain.expand([.init(skillID: Self.skillC, level: 5)])

        #expect(result == [
            .init(skillID: Self.skillA, level: 2),
            .init(skillID: Self.skillB, level: 3),
            .init(skillID: Self.skillC, level: 5),
        ])
    }

    @Test("expand collapses duplicates to the highest level")
    func expandCollapsesDuplicates() {
        let lowThenHigh = Self.chain.expand([
            .init(skillID: Self.skillC, level: 3),
            .init(skillID: Self.skillC, level: 5),
        ])
        let highThenLow = Self.chain.expand([
            .init(skillID: Self.skillC, level: 5),
            .init(skillID: Self.skillC, level: 3),
        ])

        let expected: [SkillCatalog.Requirement] = [
            .init(skillID: Self.skillA, level: 2),
            .init(skillID: Self.skillB, level: 3),
            .init(skillID: Self.skillC, level: 5),
        ]
        // The order of the input must not change the answer: both ask for C 5.
        #expect(lowThenHigh == expected)
        #expect(highThenLow == expected)
    }

    @Test("expand keeps a type the catalog does not know")
    func expandKeepsUnknownType() {
        let unknown = TypeID(rawValue: 999)
        let result = Self.chain.expand([.init(skillID: unknown, level: 1)])

        #expect(result == [.init(skillID: unknown, level: 1)])
    }

    @Test("expand terminates on a cycle instead of overflowing the stack")
    func expandSurvivesCycle() {
        // Cyclic data: A requires B, B requires A.
        let cyclic = SkillCatalog(
            skills: [
                Self.skillA: .init(rank: 1, primaryAttribute: .memory,
                                   secondaryAttribute: .intelligence,
                                   prerequisites: [.init(skillID: Self.skillB, level: 4)]),
                Self.skillB: .init(rank: 1, primaryAttribute: .memory,
                                   secondaryAttribute: .intelligence,
                                   prerequisites: [.init(skillID: Self.skillA, level: 2)]),
            ],
            implantBonuses: [:]
        )

        let result = cyclic.expand([.init(skillID: Self.skillA, level: 5)])

        // Both skills once, each at its highest level; the order inside a cycle is unspecified.
        #expect(result.count == 2)
        #expect(Set(result) == [
            .init(skillID: Self.skillA, level: 5),
            .init(skillID: Self.skillB, level: 4),
        ])
    }

    // MARK: - Implants

    @Test("attributes(ofImplants:) sums bonuses attribute by attribute")
    func implantBonusesAreSummed() {
        let memoryImplant = TypeID(rawValue: 10)
        // One type can raise several attributes at once — category 20 holds boosters too.
        let dualImplant = TypeID(rawValue: 11)
        let catalog = SkillCatalog(
            skills: [:],
            implantBonuses: [
                memoryImplant: CharacterAttributes(memory: 5),
                dualImplant: CharacterAttributes(memory: 3, perception: 4),
            ]
        )

        let total = catalog.attributes(ofImplants: [memoryImplant, dualImplant])

        #expect(total == CharacterAttributes(memory: 8, perception: 4))
        #expect(catalog.attributes(ofImplants: []) == .zero)
        // An unknown type contributes nothing rather than breaking the sum.
        #expect(catalog.attributes(ofImplants: [memoryImplant, TypeID(rawValue: 999)])
            == CharacterAttributes(memory: 5))
    }
}
