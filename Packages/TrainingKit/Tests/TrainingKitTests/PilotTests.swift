//
//  PilotTests.swift
//  TrainingKit
//

import Foundation
import Testing
import SDEKit
@testable import TrainingKit

@Suite("Pilot")
struct PilotTests {
    private static let skillA = TypeID(rawValue: 1)   // already in /skills
    private static let skillB = TypeID(rawValue: 2)   // finished in the queue, not in /skills yet
    private static let skillC = TypeID(rawValue: 3)   // training right now
    private static let unknownSkill = TypeID(rawValue: 99)   // missing from the catalog
    private static let implant = TypeID(rawValue: 100)

    private static let catalog = SkillCatalog(
        skills: [
            skillA: .init(rank: 1, primaryAttribute: .memory, secondaryAttribute: .intelligence),
            skillB: .init(rank: 2, primaryAttribute: .memory, secondaryAttribute: .intelligence),
            skillC: .init(rank: 3, primaryAttribute: .perception, secondaryAttribute: .willpower),
        ],
        implantBonuses: [implant: CharacterAttributes(perception: 3)]
    )

    // A fixed instant: nothing here may depend on the wall clock.
    private static let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private static let hour: TimeInterval = 3600

    /// Level 3 of skill B, the value the catalog fallback has to reproduce.
    private static let skillBLevel3 = TrainingMath.skillPoints(rank: 2, level: 3)

    private static let trainingStartPoints = 4000
    private static let trainingEndPoints = 8000

    private static let snapshot = CharacterSnapshot(
        attributes: CharacterAttributes(charisma: 19, intelligence: 20, memory: 20,
                                        perception: 23, willpower: 20),
        implants: [implant],
        skills: [.init(skillID: skillA, trainedLevel: 2, activeLevel: 2, skillPoints: 1414)],
        queue: [
            // Finished an hour ago; ESI sent no skill point values, so they come from the
            // catalog.
            .init(skillID: skillB, finishedLevel: 3, position: 0,
                  startDate: now - 2 * hour, finishDate: now - hour),
            // A quarter of the way through level 4: one hour of a four hour level.
            .init(skillID: skillC, finishedLevel: 4, position: 1,
                  startDate: now - hour, finishDate: now + 3 * hour,
                  levelStartSkillPoints: trainingStartPoints,
                  levelEndSkillPoints: trainingEndPoints),
        ],
        totalSkillPoints: 5_000_000
    )

    private static let pilot = Pilot(snapshot: snapshot, catalog: catalog, now: now)

    // MARK: - Rule 1: implants

    @Test("implant bonus is taken out of the ESI attributes")
    func implantsAddUp() {
        #expect(Self.pilot.baseAttributes.perception == 20)
        #expect(Self.pilot.implantBonus == CharacterAttributes(perception: 3))
        #expect(Self.pilot.attributes == CharacterAttributes(charisma: 19, intelligence: 20,
                                                             memory: 20, perception: 23,
                                                             willpower: 20))
    }

    @Test("an implant the catalog does not know contributes nothing")
    func unknownImplantIsIgnored() {
        var snapshot = Self.snapshot
        snapshot.implants = [TypeID(rawValue: 12345)]
        let pilot = Pilot(snapshot: snapshot, catalog: Self.catalog, now: Self.now)

        #expect(pilot.implantBonus == .zero)
        #expect(pilot.attributes == pilot.baseAttributes)
    }

    // MARK: - Rule 2: finished queue entries

    @Test("a queue entry finished in the past counts as a trained level")
    func finishedEntryIsCredited() {
        #expect(Self.pilot.trainedLevel(of: Self.skillB) == 3)
        #expect(Self.pilot.skillPoints(in: Self.skillB) == Self.skillBLevel3)
    }

    @Test("skills reported by ESI are kept as they are")
    func reportedSkillIsKept() {
        #expect(Self.pilot.trainedLevel(of: Self.skillA) == 2)
        #expect(Self.pilot.skillPoints(in: Self.skillA) == 1414)
    }

    @Test("a finished entry never lowers what /skills already reports")
    func finishedEntryNeverLowersASkill() {
        var snapshot = Self.snapshot
        snapshot.skills = [.init(skillID: Self.skillB, trainedLevel: 5, activeLevel: 5,
                                 skillPoints: 512_000)]
        let pilot = Pilot(snapshot: snapshot, catalog: Self.catalog, now: Self.now)

        #expect(pilot.trainedLevel(of: Self.skillB) == 5)
        #expect(pilot.skillPoints(in: Self.skillB) == 512_000)
    }

    @Test("a finished entry for a skill outside the catalog is not invented")
    func finishedEntryOfUnknownSkillIsSkipped() {
        var snapshot = Self.snapshot
        snapshot.queue = [.init(skillID: Self.unknownSkill, finishedLevel: 3, position: 0,
                                startDate: Self.now - 2 * Self.hour,
                                finishDate: Self.now - Self.hour)]
        let pilot = Pilot(snapshot: snapshot, catalog: Self.catalog, now: Self.now)

        #expect(pilot.skills[Self.unknownSkill] == nil)
        #expect(pilot.trainedLevel(of: Self.unknownSkill) == 0)
        #expect(pilot.skillPoints(in: Self.unknownSkill) == 0)
    }

    // MARK: - Rule 3: the skill being trained

    @Test("the skill being trained gets skill points between the level's ends")
    func trainingSkillIsInterpolated() {
        let points = Self.pilot.skillPoints(in: Self.skillC)

        #expect(points > Self.trainingStartPoints)
        #expect(points < Self.trainingEndPoints)
        // A quarter of a four hour level: 4000 + (8000 - 4000) * 0.25.
        #expect(points == 5000)
        // Level 4 is not finished, so the character stands at level 3.
        #expect(Self.pilot.trainedLevel(of: Self.skillC) == 3)
    }

    @Test("missing skill point values are computed from the catalog rank")
    func trainingSkillFallsBackToTheCatalog() {
        var snapshot = Self.snapshot
        snapshot.queue = [.init(skillID: Self.skillC, finishedLevel: 4, position: 0,
                                startDate: Self.now - Self.hour,
                                finishDate: Self.now + Self.hour)]
        let pilot = Pilot(snapshot: snapshot, catalog: Self.catalog, now: Self.now)

        let levelStart = TrainingMath.skillPoints(rank: 3, level: 3)
        let levelEnd = TrainingMath.skillPoints(rank: 3, level: 4)
        // Half a level, rounded: the catalog supplies both ends of the interpolation.
        #expect(pilot.skillPoints(in: Self.skillC)
                == Int((Double(levelStart + levelEnd) / 2).rounded()))
    }

    @Test("an entry that has not started yet earns nothing")
    func futureEntryEarnsNothing() {
        var snapshot = Self.snapshot
        snapshot.queue = [.init(skillID: Self.skillC, finishedLevel: 4, position: 0,
                                startDate: Self.now + Self.hour,
                                finishDate: Self.now + 5 * Self.hour,
                                levelStartSkillPoints: Self.trainingStartPoints,
                                levelEndSkillPoints: Self.trainingEndPoints)]
        let pilot = Pilot(snapshot: snapshot, catalog: Self.catalog, now: Self.now)

        #expect(pilot.skills[Self.skillC] == nil)
        #expect(pilot.queue.count == 1)
    }

    @Test("a paused entry earns nothing but stays ahead of the character")
    func pausedEntryIsSkipped() {
        var snapshot = Self.snapshot
        snapshot.queue = [.init(skillID: Self.skillC, finishedLevel: 4, position: 0,
                                levelStartSkillPoints: Self.trainingStartPoints,
                                levelEndSkillPoints: Self.trainingEndPoints)]
        let pilot = Pilot(snapshot: snapshot, catalog: Self.catalog, now: Self.now)

        #expect(pilot.skills[Self.skillC] == nil)
        #expect(pilot.queue.map(\.skillID) == [Self.skillC])
    }

    // MARK: - The queue

    @Test("queue holds only what is still ahead")
    func queueKeepsOnlyTheFuture() {
        #expect(Self.pilot.queue.map(\.skillID) == [Self.skillC])
    }

    @Test("queue is sorted by ascending position")
    func queueIsSortedByPosition() {
        var snapshot = Self.snapshot
        snapshot.queue = [
            .init(skillID: Self.skillC, finishedLevel: 5, position: 2,
                  startDate: Self.now + 3 * Self.hour, finishDate: Self.now + 4 * Self.hour),
            .init(skillID: Self.skillA, finishedLevel: 3, position: 1,
                  startDate: Self.now + Self.hour, finishDate: Self.now + 3 * Self.hour),
            .init(skillID: Self.skillB, finishedLevel: 4, position: 0,
                  startDate: Self.now - Self.hour, finishDate: Self.now + Self.hour),
        ]
        let pilot = Pilot(snapshot: snapshot, catalog: Self.catalog, now: Self.now)

        #expect(pilot.queue.map(\.position) == [0, 1, 2])
        #expect(pilot.queue.map(\.skillID) == [Self.skillB, Self.skillA, Self.skillC])
    }

    // MARK: - Pass-through

    @Test("total skill points come straight from the snapshot")
    func totalSkillPointsArePassedThrough() {
        #expect(Self.pilot.totalSkillPoints == 5_000_000)
    }
}
