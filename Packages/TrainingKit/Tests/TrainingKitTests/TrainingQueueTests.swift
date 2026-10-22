//
//  TrainingQueueTests.swift
//  TrainingKit
//

import Foundation
import Testing
import SDEKit
@testable import TrainingKit

@Suite("TrainingQueue")
struct TrainingQueueTests {
    // The catalog: C requires B at 3, B requires A at 2, A requires nothing.
    private static let skillA = TypeID(rawValue: 1)
    private static let skillB = TypeID(rawValue: 2)
    private static let skillC = TypeID(rawValue: 3)
    private static let unknownSkill = TypeID(rawValue: 99)   // missing from the catalog
    private static let implant = TypeID(rawValue: 100)

    private static let catalog = SkillCatalog(
        skills: [
            skillA: .init(rank: 1, primaryAttribute: .memory, secondaryAttribute: .intelligence),
            skillB: .init(rank: 2, primaryAttribute: .memory, secondaryAttribute: .intelligence,
                          prerequisites: [.init(skillID: skillA, level: 2)]),
            skillC: .init(rank: 3, primaryAttribute: .perception, secondaryAttribute: .willpower,
                          prerequisites: [.init(skillID: skillB, level: 3)]),
        ],
        implantBonuses: [implant: CharacterAttributes(perception: 3)]
    )

    // A fixed instant: nothing here may depend on the wall clock.
    private static let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private static let hour: TimeInterval = 3600

    private static let baseAttributes = CharacterAttributes(charisma: 19, intelligence: 20,
                                                            memory: 20, perception: 20,
                                                            willpower: 20)

    /// A trained to II, B finished at III in the queue, C a quarter of
    /// the way through IV — so C stands at III.
    private static let pilot = Pilot(
        snapshot: CharacterSnapshot(
            attributes: baseAttributes,
            implants: [implant],
            skills: [.init(skillID: skillA, trainedLevel: 2, activeLevel: 2, skillPoints: 1414)],
            queue: [
                .init(skillID: skillB, finishedLevel: 3, position: 0,
                      startDate: now - 2 * hour, finishDate: now - hour),
                .init(skillID: skillC, finishedLevel: 4, position: 1,
                      startDate: now - hour, finishDate: now + 3 * hour,
                      levelStartSkillPoints: 4000, levelEndSkillPoints: 8000),
            ],
            totalSkillPoints: 5_000_000
        ),
        catalog: catalog,
        now: now
    )

    /// A character who has trained nothing, so the whole prerequisite chain is queued.
    private static let rookie = Pilot(
        snapshot: CharacterSnapshot(attributes: baseAttributes, implants: [], skills: [],
                                    queue: [], totalSkillPoints: 0),
        catalog: catalog,
        now: now
    )

    private static func levels(_ queue: TrainingQueue) -> [SkillCatalog.Requirement] {
        queue.items.map { .init(skillID: $0.skillID, level: $0.targetLevel) }
    }

    // MARK: - What lands in the queue

    @Test("a skill to V adds one item per level still missing")
    func addsOneItemPerLevel() {
        var queue = TrainingQueue(pilot: Self.pilot, catalog: Self.catalog)
        queue.add(skill: Self.skillC, level: 5)

        // A II and B III are already trained, so only the two missing levels of C remain.
        #expect(Self.levels(queue) == [
            .init(skillID: Self.skillC, level: 4),
            .init(skillID: Self.skillC, level: 5),
        ])
        #expect(!queue.isEmpty)
    }

    @Test("levels the character already has are not planned again")
    func trainedLevelsAreSkipped() {
        var queue = TrainingQueue(pilot: Self.pilot, catalog: Self.catalog)
        // The pilot is already at III in both, so asking for less than that adds nothing.
        queue.add(skill: Self.skillB, level: 3)
        queue.add(skill: Self.skillC, level: 2)

        #expect(queue.isEmpty)
        #expect(queue.totalTime == 0)
    }

    @Test("prerequisites come before the skill that needs them")
    func prerequisitesComeFirst() {
        var queue = TrainingQueue(pilot: Self.rookie, catalog: Self.catalog)
        queue.add(skill: Self.skillC, level: 5)

        #expect(Self.levels(queue) == [
            .init(skillID: Self.skillA, level: 1),
            .init(skillID: Self.skillA, level: 2),
            .init(skillID: Self.skillB, level: 1),
            .init(skillID: Self.skillB, level: 2),
            .init(skillID: Self.skillB, level: 3),
            .init(skillID: Self.skillC, level: 1),
            .init(skillID: Self.skillC, level: 2),
            .init(skillID: Self.skillC, level: 3),
            .init(skillID: Self.skillC, level: 4),
            .init(skillID: Self.skillC, level: 5),
        ])
    }

    @Test("adding the same thing twice changes nothing")
    func addingTwiceIsANoOp() {
        var queue = TrainingQueue(pilot: Self.rookie, catalog: Self.catalog)
        queue.add(skill: Self.skillC, level: 5)
        let once = queue.items

        queue.add(skill: Self.skillC, level: 5)
        // The same levels reached the second time as someone else's prerequisites, too.
        queue.add(skill: Self.skillB, level: 3)

        #expect(queue.items == once)
    }

    @Test("a skill outside the catalog does not reach the queue")
    func unknownSkillIsNotPlanned() {
        var queue = TrainingQueue(pilot: Self.rookie, catalog: Self.catalog)
        queue.add(skill: Self.unknownSkill, level: 3)

        // `expand` passes unknown types through; the queue drops them.
        #expect(queue.isEmpty)
        #expect(queue.time(forSkill: Self.unknownSkill, level: 3) == nil)

        // Mixed in with a known requirement it disappears without taking it down.
        queue.add(requirements: [.init(skillID: Self.unknownSkill, level: 3),
                                 .init(skillID: Self.skillA, level: 2)])
        #expect(Self.levels(queue) == [
            .init(skillID: Self.skillA, level: 1),
            .init(skillID: Self.skillA, level: 2),
        ])
    }

    @Test("item requirements are expanded like any other target")
    func requirementsAreExpanded() {
        var queue = TrainingQueue(pilot: Self.rookie, catalog: Self.catalog)
        // Two requirements, the second a prerequisite of the first.
        queue.add(requirements: [.init(skillID: Self.skillC, level: 1),
                                 .init(skillID: Self.skillB, level: 2)])

        #expect(Self.levels(queue) == [
            .init(skillID: Self.skillA, level: 1),
            .init(skillID: Self.skillA, level: 2),
            .init(skillID: Self.skillB, level: 1),
            .init(skillID: Self.skillB, level: 2),
            .init(skillID: Self.skillB, level: 3),   // C asks for III, and III wins
            .init(skillID: Self.skillC, level: 1),
        ])
    }

    // MARK: - Skill points

    @Test("the first level added starts from the points the character has")
    func firstLevelStartsFromTheCharactersPoints() {
        var queue = TrainingQueue(pilot: Self.pilot, catalog: Self.catalog)
        queue.add(skill: Self.skillC, level: 5)

        let levelThree = TrainingMath.skillPoints(rank: 3, level: 3)
        let levelFour = TrainingMath.skillPoints(rank: 3, level: 4)
        let levelFive = TrainingMath.skillPoints(rank: 3, level: 5)

        // The pilot holds 5000 points in C — below the end of level III, so the level's
        // own end is the larger of the two and wins.
        #expect(Self.pilot.skillPoints(in: Self.skillC) == 5000)
        #expect(queue.items[0].startSkillPoints == levelThree)
        #expect(queue.items[0].finishSkillPoints == levelFour)
        // Every further level picks up where the previous one ends.
        #expect(queue.items[1].startSkillPoints == levelFour)
        #expect(queue.items[1].finishSkillPoints == levelFive)
    }

    @Test("a partly trained skill is not trained from the start of the level again")
    func partlyTrainedSkillKeepsItsPoints() {
        // A at level II with more points than level II requires: the character is part
        // of the way into level III.
        let partial = Pilot(
            snapshot: CharacterSnapshot(
                attributes: Self.baseAttributes, implants: [],
                skills: [.init(skillID: Self.skillA, trainedLevel: 2, activeLevel: 2,
                               skillPoints: 3000)],
                queue: [], totalSkillPoints: 3000
            ),
            catalog: Self.catalog, now: Self.now
        )
        var queue = TrainingQueue(pilot: partial, catalog: Self.catalog)
        queue.add(skill: Self.skillA, level: 3)

        let levelTwo = TrainingMath.skillPoints(rank: 1, level: 2)
        #expect(levelTwo < 3000)
        #expect(queue.items.count == 1)
        #expect(queue.items[0].startSkillPoints == 3000)
        #expect(queue.items[0].finishSkillPoints == TrainingMath.skillPoints(rank: 1, level: 3))
    }

    // MARK: - Time

    @Test("time comes from the pilot's attributes and the skill's")
    func timeUsesTheSkillsAttributes() {
        var queue = TrainingQueue(pilot: Self.pilot, catalog: Self.catalog)
        queue.add(skill: Self.skillC, level: 5)

        let item = queue.items[0]
        // C trains on perception (20 + 3 from the implant) and willpower (20).
        let expected = TrainingMath.trainingTime(
            skillPoints: item.finishSkillPoints - item.startSkillPoints,
            primary: 23, secondary: 20
        )
        #expect(item.trainingTime == expected)
        #expect(queue.time(forSkill: Self.skillC, level: 4) == expected)
        #expect(queue.time(forSkill: Self.skillC, level: 3) == nil)
    }

    @Test("totalTime is the sum of the items")
    func totalTimeIsTheSum() {
        var queue = TrainingQueue(pilot: Self.rookie, catalog: Self.catalog)
        queue.add(skill: Self.skillC, level: 5)

        #expect(queue.totalTime == queue.items.reduce(0) { $0 + $1.trainingTime })
        #expect(queue.totalTime > 0)
        #expect(TrainingQueue(pilot: Self.rookie, catalog: Self.catalog).totalTime == 0)
    }

    // MARK: - remove

    @Test("remove takes the level and everything above it in the same skill")
    func removeDropsHigherLevelsToo() {
        var queue = TrainingQueue(pilot: Self.rookie, catalog: Self.catalog)
        queue.add(skill: Self.skillC, level: 5)
        let before = queue.totalTime

        let removed = queue.items.first { $0.skillID == Self.skillC && $0.targetLevel == 3 }!
        queue.remove(removed)

        // C IV and V go with it — they cannot be trained without III. The other skills
        // and the lower levels of C stay.
        #expect(Self.levels(queue) == [
            .init(skillID: Self.skillA, level: 1),
            .init(skillID: Self.skillA, level: 2),
            .init(skillID: Self.skillB, level: 1),
            .init(skillID: Self.skillB, level: 2),
            .init(skillID: Self.skillB, level: 3),
            .init(skillID: Self.skillC, level: 1),
            .init(skillID: Self.skillC, level: 2),
        ])
        #expect(queue.totalTime < before)
    }

    @Test("removing the lowest level of a skill removes the whole skill")
    func removeOfTheFirstLevelClearsTheSkill() {
        var queue = TrainingQueue(pilot: Self.pilot, catalog: Self.catalog)
        queue.add(skill: Self.skillC, level: 5)
        queue.remove(queue.items[0])

        #expect(queue.isEmpty)
    }
}
