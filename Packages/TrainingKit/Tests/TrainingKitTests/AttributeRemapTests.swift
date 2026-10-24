//
//  AttributeRemapTests.swift
//  TrainingKit
//

import Foundation
import Testing
import SDEKit
@testable import TrainingKit

@Suite("AttributeRemap")
struct AttributeRemapTests {
    private static func item(_ primary: CharacterAttribute, _ secondary: CharacterAttribute,
                             points: Int = 1_000_000) -> TrainingQueue.Item {
        TrainingQueue.Item(skillID: TypeID(rawValue: 1), targetLevel: 1,
                           startSkillPoints: 0, finishSkillPoints: points, trainingTime: 0,
                           primaryAttribute: primary, secondaryAttribute: secondary)
    }

    private static let current = CharacterAttributes(charisma: 19, intelligence: 20,
                                                     memory: 20, perception: 20, willpower: 20)

    @Test("the game accepts 2 885 distributions, all of them valid")
    func distributions() {
        let all = AttributeRemap.distributions
        #expect(all.count == 2885)
        #expect(Set(all).count == all.count)
        for attributes in all {
            let values = CharacterAttribute.allCases.map { attributes[$0] }
            #expect(values.allSatisfy { AttributeRemap.range.contains($0) })
            #expect(values.reduce(0, +) == AttributeRemap.total)
        }
    }

    @Test("a plan on Perception and Willpower puts the points there")
    func perceptionWillpower() throws {
        let remap = try #require(AttributeRemap.optimal(for: [Self.item(.perception, .willpower)],
                                                        current: Self.current, implants: .zero))
        #expect(remap.optimal.perception == 27)
        #expect(remap.optimal.willpower == 21)
        #expect(remap.optimal.charisma == 17)
        #expect(remap.optimal.intelligence == 17)
        #expect(remap.optimal.memory == 17)
        #expect(remap.isChanged)
        #expect(remap.optimalTime < remap.currentTime)
        #expect(remap.savedTime == remap.currentTime - remap.optimalTime)
    }

    @Test("an optimal distribution is not changed")
    func alreadyOptimal() throws {
        let best = CharacterAttributes(charisma: 17, intelligence: 17, memory: 17, perception: 27, willpower: 21)
        let remap = try #require(AttributeRemap.optimal(for: [Self.item(.perception, .willpower)],
                                                        current: best, implants: .zero))
        #expect(!remap.isChanged)
        #expect(remap.savedTime == 0)
        #expect(remap.optimal == best)
    }

    @Test("among equal times the attribute the plan does not use stays where it is")
    func tieBreak() throws {
        // Charisma and Intelligence are unused, so only the closeness to the current
        // distribution tells the candidates apart.
        let current = CharacterAttributes(charisma: 18, intelligence: 16 + 1, memory: 17,
                                          perception: 27, willpower: 20)
        let remap = try #require(AttributeRemap.optimal(for: [Self.item(.perception, .willpower)],
                                                        current: current, implants: .zero))
        #expect(remap.optimal.perception == 27)
        #expect(remap.optimal.willpower == 21)
        #expect(remap.optimal.charisma == 18 || remap.optimal.charisma == 17)
        // One point has to move to Willpower; it comes from the nearest unused attribute.
        let moved = CharacterAttribute.allCases.reduce(0) { $0 + abs(remap.optimal[$1] - current[$1]) }
        #expect(moved == 2)
    }

    @Test("no items, no remap")
    func empty() {
        #expect(AttributeRemap.optimal(for: [], current: Self.current, implants: .zero) == nil)
    }

    @Test("implants count in the time but not in the bounds")
    func implants() throws {
        let implants = CharacterAttributes(perception: 5)
        let remap = try #require(AttributeRemap.optimal(for: [Self.item(.perception, .willpower)],
                                                        current: Self.current, implants: implants))
        // The base stays within 17...27 whatever the implant adds.
        #expect(remap.optimal.perception == 27)
        #expect(remap.optimal.willpower == 21)

        // The current time is timed with the implant: 1 000 000 points at (25 + 10) / 60.
        let expected = TrainingMath.trainingTime(skillPoints: 1_000_000, primary: 25, secondary: 20)
        #expect(remap.currentTime == expected)

        // A plan on Memory/Intelligence next to a Perception implant ignores the implant's
        // attribute entirely.
        let other = try #require(AttributeRemap.optimal(for: [Self.item(.memory, .intelligence)],
                                                        current: Self.current, implants: implants))
        #expect(other.optimal.memory == 27)
        #expect(other.optimal.intelligence == 21)
    }

    @Test("a pilot's plan is optimised from the base attributes, not from ESI's implant-inclusive ones")
    func pilotPlan() throws {
        let implantIDs = (1...5).map { TypeID(rawValue: UInt32(100 + $0)) }
        let implantBonuses = Dictionary(uniqueKeysWithValues: zip(implantIDs, [
            CharacterAttributes(charisma: 4), CharacterAttributes(intelligence: 4),
            CharacterAttributes(memory: 4), CharacterAttributes(perception: 4),
            CharacterAttributes(willpower: 4),
        ]))
        let skills: [(CharacterAttribute, CharacterAttribute, Double)] = [
            (.intelligence, .memory, 12), (.intelligence, .memory, 8), (.memory, .intelligence, 10),
            (.memory, .intelligence, 6), (.perception, .willpower, 5), (.willpower, .perception, 4),
        ]
        var catalogSkills: [TypeID: SkillCatalog.Skill] = [:]
        for (index, skill) in skills.enumerated() {
            catalogSkills[TypeID(rawValue: UInt32(index + 1))] = .init(rank: skill.2, primaryAttribute: skill.0,
                                                                        secondaryAttribute: skill.1)
        }
        let catalog = SkillCatalog(skills: catalogSkills, implantBonuses: implantBonuses)
        // ESI reports base 19/20/20/20/20 plus five +4 implants.
        let snapshot = CharacterSnapshot(
            attributes: CharacterAttributes(charisma: 23, intelligence: 24, memory: 24,
                                            perception: 24, willpower: 24),
            implants: implantIDs, skills: [], queue: [], totalSkillPoints: 0)
        var queue = TrainingQueue(pilot: Pilot(snapshot: snapshot, catalog: catalog), catalog: catalog)
        queue.add(requirements: catalogSkills.keys.map { .init(skillID: $0, level: 5) })

        let remap = try #require(queue.optimalRemap())
        #expect(remap.current == Self.current)
        #expect(abs(remap.currentTime - queue.totalTime) < 1e-3)

        // Brute force over every valid distribution.
        let implants = CharacterAttributes(charisma: 4, intelligence: 4, memory: 4, perception: 4, willpower: 4)
        var bestTime = TimeInterval.infinity
        var best = Self.current
        for c in 17...27 { for i in 17...27 { for m in 17...27 { for p in 17...27 {
            let w = 99 - c - i - m - p
            guard (17...27).contains(w) else { continue }
            let base = CharacterAttributes(charisma: c, intelligence: i, memory: m, perception: p, willpower: w)
            let total = base + implants
            let time = queue.items.reduce(0) {
                $0 + TrainingMath.trainingTime(skillPoints: $1.skillPoints,
                                               primary: total[$1.primaryAttribute],
                                               secondary: total[$1.secondaryAttribute])
            }
            if time < bestTime { bestTime = time; best = base }
        }}}}

        #expect(remap.isChanged)
        #expect(abs(remap.optimalTime - bestTime) < 1e-3)
        #expect(remap.optimal == best)
        #expect(remap.optimal.charisma == 17)
        #expect(remap.optimal.intelligence > remap.optimal.perception)
    }

    @Test("remap availability follows the bank and the date")
    func availability() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(RemapAvailability(bonusRemaps: 1, nextNeuralRemap: now + 100).isAvailable(at: now))
        #expect(RemapAvailability(bonusRemaps: 0, nextNeuralRemap: now - 1).isAvailable(at: now))
        #expect(!RemapAvailability(bonusRemaps: 0, nextNeuralRemap: now + 1).isAvailable(at: now))
        #expect(!RemapAvailability(bonusRemaps: 0, nextNeuralRemap: nil).isAvailable(at: now))

        let empty = CharacterSnapshot(attributes: Self.current, implants: [], skills: [],
                                      queue: [], totalSkillPoints: 0)
        #expect(RemapAvailability(snapshot: empty) == nil)
        var accrued = empty
        accrued.accruedRemapCooldownDate = now
        #expect(RemapAvailability(snapshot: accrued)?.nextNeuralRemap == now)
    }
}
