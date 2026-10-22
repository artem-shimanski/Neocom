//
//  TrainingRemindersTests.swift
//  TrainingKit
//

import Foundation
import Testing
import SDEKit
@testable import TrainingKit

@Suite("TrainingReminders")
struct TrainingRemindersTests {
    private static let now = Date(timeIntervalSince1970: 1_792_238_400)
    private static let hour: TimeInterval = 3600

    private static func entry(_ skill: UInt32, level: Int, position: Int, finishIn hours: Double?) -> CharacterSnapshot.QueueEntry {
        CharacterSnapshot.QueueEntry(skillID: TypeID(rawValue: skill), finishedLevel: level, position: position,
                                     finishDate: hours.map { now.addingTimeInterval($0 * hour) })
    }

    private static let queue = [
        entry(1, level: 4, position: 0, finishIn: 2),
        entry(2, level: 3, position: 1, finishIn: 30),
        entry(3, level: 5, position: 2, finishIn: 80),
    ]

    @Test func everySkillAndTheQueueEnd() {
        let plan = TrainingReminders.plan(queue: Self.queue, skillTrained: true, queueEnding: true, leadHours: 12, now: Self.now)
        #expect(plan.map(\.id) == ["skill.1.4", "skill.2.3", "queue-end", "skill.3.5"])
        let end = plan.first { $0.id == "queue-end" }
        #expect(end?.fireDate == Self.now.addingTimeInterval(68 * Self.hour))
        #expect(end?.eventDate == Self.now.addingTimeInterval(80 * Self.hour))
        #expect(end?.kind == .queueEnding(skillID: TypeID(rawValue: 3), level: 5, leadHours: 12))
    }

    @Test func kindsOff() {
        let skills = TrainingReminders.plan(queue: Self.queue, skillTrained: true, queueEnding: false, leadHours: 12, now: Self.now)
        #expect(skills.count == 3)
        let end = TrainingReminders.plan(queue: Self.queue, skillTrained: false, queueEnding: true, leadHours: 0, now: Self.now)
        #expect(end.map(\.id) == ["queue-end"])
        #expect(end.first?.fireDate == Self.now.addingTimeInterval(80 * Self.hour))
        #expect(TrainingReminders.plan(queue: Self.queue, skillTrained: false, queueEnding: false, leadHours: 0, now: Self.now).isEmpty)
    }

    @Test func pastMomentsAreLeftOut() {
        let queue = [Self.entry(1, level: 1, position: 0, finishIn: -1), Self.entry(2, level: 2, position: 1, finishIn: 5)]
        let plan = TrainingReminders.plan(queue: queue, skillTrained: true, queueEnding: true, leadHours: 12, now: Self.now)
        // The trained skill is gone; the queue's lead window has already begun.
        #expect(plan.map(\.id) == ["skill.2.2"])
    }

    @Test func pausedQueueSchedulesNothing() {
        let paused = [Self.entry(1, level: 1, position: 0, finishIn: nil), Self.entry(2, level: 2, position: 1, finishIn: nil)]
        #expect(TrainingReminders.plan(queue: paused, skillTrained: true, queueEnding: true, leadHours: 1, now: Self.now).isEmpty)
        #expect(TrainingReminders.state(of: paused, now: Self.now) == .paused)
        #expect(TrainingReminders.state(of: [], now: Self.now) == .empty)
        #expect(TrainingReminders.state(of: [Self.entry(1, level: 1, position: 0, finishIn: -2)], now: Self.now) == .empty)
        #expect(TrainingReminders.state(of: Self.queue, now: Self.now) == .training(until: Self.now.addingTimeInterval(80 * Self.hour)))
    }
}
