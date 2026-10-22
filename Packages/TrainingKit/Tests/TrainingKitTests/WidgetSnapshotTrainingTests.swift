//
//  WidgetSnapshotTrainingTests.swift
//  TrainingKit
//

import Foundation
import Testing
import SDEKit
import TrainingTimeline
@testable import TrainingKit

@Suite("WidgetSnapshot from CharacterSnapshot")
struct WidgetSnapshotTrainingTests {
    private static let skillA = TypeID(rawValue: 1)
    private static let skillB = TypeID(rawValue: 2)
    private static let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private static let hour: TimeInterval = 3600

    private static let catalog = SkillCatalog(
        skills: [
            skillA: .init(rank: 1, primaryAttribute: .memory, secondaryAttribute: .intelligence),
            skillB: .init(rank: 2, primaryAttribute: .memory, secondaryAttribute: .intelligence),
        ],
        implantBonuses: [:]
    )

    // 20 + 20 / 2 = 30 points a minute: half a point a second.
    private static let attributes = CharacterAttributes(charisma: 20, intelligence: 20, memory: 20,
                                                        perception: 20, willpower: 20)

    private static func snapshot(_ queue: [CharacterSnapshot.QueueEntry]) -> CharacterSnapshot {
        CharacterSnapshot(attributes: attributes, implants: [],
                          skills: [.init(skillID: skillA, trainedLevel: 3, activeLevel: 3, skillPoints: 10_000)],
                          queue: queue, totalSkillPoints: 1_000_000)
    }

    private static func name(_ id: TypeID) -> String { "Skill \(id.rawValue)" }

    @Test func datedEntries() {
        // A to IV started part of the way in (10 000 of 8 000…45 255), then A to V, then B to I.
        let queue = [
            CharacterSnapshot.QueueEntry(skillID: Self.skillA, finishedLevel: 4, position: 0,
                                         startDate: Self.now - Self.hour, finishDate: Self.now + Self.hour,
                                         levelStartSkillPoints: 8000, levelEndSkillPoints: 45_255),
            CharacterSnapshot.QueueEntry(skillID: Self.skillA, finishedLevel: 5, position: 1,
                                         startDate: Self.now + Self.hour, finishDate: Self.now + 5 * Self.hour,
                                         levelStartSkillPoints: 45_255, levelEndSkillPoints: 256_000),
            // ESI left the points out: the catalog's rank stands in.
            CharacterSnapshot.QueueEntry(skillID: Self.skillB, finishedLevel: 1, position: 2,
                                         startDate: Self.now + 5 * Self.hour, finishDate: Self.now + 6 * Self.hour),
        ]
        let training = WidgetSnapshot.Training(snapshot: Self.snapshot(queue), fetchedAt: Self.now,
                                               catalog: Self.catalog, name: Self.name)
        #expect(training.fetchedAt == Self.now)
        #expect(training.queue.map(\.name) == ["Skill 1", "Skill 1", "Skill 2"])
        #expect(training.queue.map(\.trainingStartSkillPoints) == [10_000, 45_255, 0])
        #expect(training.queue[2].levelEndSkillPoints == 500)
        #expect(training.queue.map(\.duration) == [2 * Self.hour, 4 * Self.hour, Self.hour])
        #expect(training.idleSince == nil)
    }

    @Test func pausedEntriesGetAnEstimate() {
        let queue = [
            CharacterSnapshot.QueueEntry(skillID: Self.skillA, finishedLevel: 4, position: 0,
                                         levelStartSkillPoints: 8000, levelEndSkillPoints: 45_255),
        ]
        let training = WidgetSnapshot.Training(snapshot: Self.snapshot(queue), fetchedAt: Self.now,
                                               catalog: Self.catalog, name: Self.name)
        // 35 255 points left at half a point a second.
        #expect(training.queue.first?.duration == 70_510)
        #expect(training.queue.first?.startDate == nil)

        let blind = WidgetSnapshot.Training(snapshot: Self.snapshot(queue), fetchedAt: Self.now,
                                            catalog: nil, name: Self.name)
        #expect(blind.queue.first?.duration == nil)
    }

    @Test func emptyQueueCarriesTheLastFinish() {
        let finish = Self.now - 3 * Self.hour
        let previous = WidgetSnapshot.Training(fetchedAt: Self.now - 10 * Self.hour, queue: [
            WidgetSnapshot.QueueEntry(skillID: 1, name: "Skill 1", level: 4,
                                      startDate: Self.now - 11 * Self.hour, finishDate: finish,
                                      levelStartSkillPoints: 8000, levelEndSkillPoints: 45_255,
                                      trainingStartSkillPoints: 8000, duration: 8 * Self.hour),
        ])
        let empty = WidgetSnapshot.Training(snapshot: Self.snapshot([]), fetchedAt: Self.now,
                                            catalog: Self.catalog, previous: previous, name: Self.name)
        #expect(empty.idleSince == finish)

        // And keeps it on the next empty fetch.
        let again = WidgetSnapshot.Training(snapshot: Self.snapshot([]), fetchedAt: Self.now + Self.hour,
                                            catalog: Self.catalog, previous: empty, name: Self.name)
        #expect(again.idleSince == finish)

        // A queue cleared before it ran out: when it stopped is not known.
        let cleared = WidgetSnapshot.Training(snapshot: Self.snapshot([]), fetchedAt: finish - Self.hour,
                                              catalog: Self.catalog, previous: previous, name: Self.name)
        #expect(cleared.idleSince == nil)
    }

    @Test func planSkipsWhatIsTrained() {
        let pilot = Pilot(snapshot: Self.snapshot([]), catalog: Self.catalog, now: Self.now)
        let plan = WidgetSnapshot.PlanEntry.entries(
            plan: [.init(skillID: Self.skillA, level: 3), .init(skillID: Self.skillA, level: 4),
                   .init(skillID: Self.skillB, level: 1), .init(skillID: Self.skillB, level: 2)],
            pilot: pilot, catalog: Self.catalog, limit: 2, name: Self.name)
        #expect(plan.map(\.skillID) == [1, 2])
        #expect(plan.map(\.level) == [4, 1])
        // A to IV from the 10 000 already in it: 35 255 points.
        #expect(plan.first?.duration == 70_510)
    }
}
