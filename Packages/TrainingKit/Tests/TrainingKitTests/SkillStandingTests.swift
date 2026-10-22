//
//  SkillStandingTests.swift
//  TrainingKit
//

import Foundation
import Testing
import SDEKit
@testable import TrainingKit

@Suite("Skill standing")
struct SkillStandingTests {
    private static let maxed = TypeID(rawValue: 1)      // injected at V
    private static let partial = TypeID(rawValue: 2)    // injected at II, training III
    private static let book = TypeID(rawValue: 3)       // not injected, needs maxed I
    private static let locked = TypeID(rawValue: 4)     // not injected, needs partial IV and maxed V
    private static let zero = TypeID(rawValue: 5)       // injected at level 0

    private static let catalog = SkillCatalog(
        skills: [
            maxed: .init(rank: 1, primaryAttribute: .memory, secondaryAttribute: .intelligence),
            partial: .init(rank: 2, primaryAttribute: .memory, secondaryAttribute: .intelligence),
            book: .init(rank: 3, primaryAttribute: .memory, secondaryAttribute: .intelligence,
                        prerequisites: [.init(skillID: maxed, level: 1)]),
            locked: .init(rank: 5, primaryAttribute: .memory, secondaryAttribute: .intelligence,
                          prerequisites: [.init(skillID: partial, level: 4),
                                          .init(skillID: maxed, level: 5)]),
            zero: .init(rank: 1, primaryAttribute: .memory, secondaryAttribute: .intelligence),
        ],
        implantBonuses: [:]
    )

    private static let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private static func pilot(paused: Bool) -> Pilot {
        let hour: TimeInterval = 3600
        let queue: [CharacterSnapshot.QueueEntry] = paused
            ? [.init(skillID: partial, finishedLevel: 3, position: 0),
               .init(skillID: partial, finishedLevel: 4, position: 1),
               .init(skillID: zero, finishedLevel: 1, position: 2)]
            : [.init(skillID: partial, finishedLevel: 3, position: 0,
                     startDate: now + hour, finishDate: now + 2 * hour),
               .init(skillID: partial, finishedLevel: 4, position: 1,
                     startDate: now + 2 * hour, finishDate: now + 3 * hour),
               .init(skillID: zero, finishedLevel: 1, position: 2,
                     startDate: now + 3 * hour, finishDate: now + 4 * hour)]
        let snapshot = CharacterSnapshot(
            attributes: CharacterAttributes(charisma: 20, intelligence: 20, memory: 20,
                                            perception: 20, willpower: 20),
            implants: [],
            skills: [.init(skillID: maxed, trainedLevel: 5, activeLevel: 5, skillPoints: 256_000),
                     .init(skillID: partial, trainedLevel: 2, activeLevel: 2, skillPoints: 2_829),
                     .init(skillID: zero, trainedLevel: 0, activeLevel: 0, skillPoints: 0)],
            queue: queue,
            totalSkillPoints: 258_829
        )
        return Pilot(snapshot: snapshot, catalog: catalog, now: now)
    }

    private static func standing(_ skill: TypeID, plannedLevel: Int = 0, paused: Bool = true) -> SkillStanding {
        SkillStanding(skill: skill, pilot: pilot(paused: paused), catalog: catalog, plannedLevel: plannedLevel)
    }

    @Test func states() {
        #expect(Self.standing(Self.maxed).state == .trainedToV)
        #expect(Self.standing(Self.partial).state == .canTrain)
        #expect(Self.standing(Self.zero).state == .canTrain)
        #expect(Self.standing(Self.book).state == .needsBook)
        #expect(Self.standing(Self.locked).state == .locked)
    }

    @Test func lockedListsOnlyWhatIsMissing() {
        // maxed V is trained; partial IV is only queued, which does not count.
        #expect(Self.standing(Self.locked).missing == [.init(skillID: Self.partial, level: 4)])
        #expect(Self.standing(Self.book).missing.isEmpty)
    }

    @Test func pausedQueueMarks() {
        let standing = Self.standing(Self.partial, plannedLevel: 5)
        #expect(standing.marks == [.trained, .trained, .training(paused: true), .queued, .planned])
        #expect(standing.isQueued)
        #expect(standing.isPlanned)
    }

    @Test func activeQueueMarks() {
        let standing = Self.standing(Self.partial, paused: false)
        #expect(standing.marks == [.trained, .trained, .training(paused: false), .queued, .empty])
        #expect(!standing.isPlanned)
    }

    @Test func queuedBehindAnotherSkill() {
        let standing = Self.standing(Self.zero)
        #expect(standing.isInjected)
        #expect(standing.marks == [.queued, .empty, .empty, .empty, .empty])
        #expect(standing.showsLevelBar)
    }

    @Test func plannedBookGetsTheBar() {
        let unplanned = Self.standing(Self.book)
        #expect(!unplanned.showsLevelBar)

        let planned = Self.standing(Self.book, plannedLevel: 3)
        #expect(planned.state == .needsBook)
        #expect(planned.showsLevelBar)
        #expect(planned.marks == [.planned, .planned, .planned, .empty, .empty])
    }

    @Test func planAtOrBelowTrainedIsNotPlanned() {
        #expect(!Self.standing(Self.maxed, plannedLevel: 5).isPlanned)
        #expect(!Self.standing(Self.partial, plannedLevel: 2).isPlanned)
    }

    @Test func tally() {
        let pilot = Self.pilot(paused: true)
        let standings = [Self.maxed, Self.partial, Self.book, Self.locked, Self.zero].map {
            SkillStanding(skill: $0, pilot: pilot, catalog: Self.catalog,
                          plannedLevel: $0 == Self.book ? 1 : 0)
        }
        let tally = SkillTally(standings)
        #expect(tally.total == 5)
        #expect(tally.injected == 3)
        #expect(tally.skillPoints == 258_829)
        #expect(tally.trainedToV == 1)
        #expect(tally.canTrain == 2)
        #expect(tally.needsBook == 1)
        #expect(tally.locked == 1)
        #expect(tally.queued == 2)
        #expect(tally.planned == 1)
        #expect(tally.queueMark == .training(paused: true))

        // Only the skill queued behind another one: the group's chip says queued.
        let behind = SkillTally([standings[4]])
        #expect(behind.queueMark == .queued)
        #expect(SkillTally([standings[0]]).queueMark == nil)
    }
}
