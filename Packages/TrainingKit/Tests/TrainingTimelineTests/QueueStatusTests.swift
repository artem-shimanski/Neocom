//
//  QueueStatusTests.swift
//  TrainingTimeline
//

import Foundation
import Testing
@testable import TrainingTimeline

@Suite("QueueStatus")
struct QueueStatusTests {
    private static let now = Date(timeIntervalSince1970: 1_792_238_400)
    private static let hour: TimeInterval = 3600

    /// A dated entry from `start` to `finish` hours from `now`, 1 000 points to go.
    private static func entry(_ skill: Int64, level: Int, start: Double, finish: Double,
                              startPoints: Int = 1000) -> WidgetSnapshot.QueueEntry {
        WidgetSnapshot.QueueEntry(skillID: skill, name: "Skill \(skill)", level: level,
                                  startDate: now.addingTimeInterval(start * hour),
                                  finishDate: now.addingTimeInterval(finish * hour),
                                  levelStartSkillPoints: 1000, levelEndSkillPoints: 2000,
                                  trainingStartSkillPoints: startPoints,
                                  duration: (finish - start) * hour)
    }

    private static func paused(_ skill: Int64, level: Int, points: Int) -> WidgetSnapshot.QueueEntry {
        WidgetSnapshot.QueueEntry(skillID: skill, name: "Skill \(skill)", level: level,
                                  startDate: nil, finishDate: nil,
                                  levelStartSkillPoints: 1000, levelEndSkillPoints: 2000,
                                  trainingStartSkillPoints: points, duration: 5 * hour)
    }

    private static func pilot(_ queue: [WidgetSnapshot.QueueEntry], fetchedAgo hours: Double = 0,
                              idleSince: Date? = nil, id: Int64 = 1) -> WidgetSnapshot.Pilot {
        WidgetSnapshot.Pilot(id: id, name: "Pilot \(id)",
                             training: .init(fetchedAt: now.addingTimeInterval(-hours * hour),
                                             queue: queue, idleSince: idleSince))
    }

    private static let queue = [
        entry(1, level: 4, start: -1, finish: 3),
        entry(2, level: 3, start: 3, finish: 10),
        entry(3, level: 1, start: 10, finish: 30),
        entry(4, level: 2, start: 30, finish: 40),
    ]

    @Test func training() {
        let status = QueueStatus(pilot: Self.pilot(Self.queue), now: Self.now)
        #expect(status.phase == .training)
        #expect(status.current?.name == "Skill 1")
        #expect(status.current?.level == 4)
        #expect(status.current?.trainedLevel == 3)
        // A quarter of the time, a quarter of the points.
        #expect(status.current?.progress == 0.25)
        #expect(status.current?.skillPoints == 1250)
        #expect(status.next.map(\.skillID) == [2, 3, 4])
        #expect(status.remainingCount == 3)
        #expect(status.queueEnd == Self.now.addingTimeInterval(40 * Self.hour))
        #expect(!status.isStale)
    }

    @Test func nextIsLimited() {
        let status = QueueStatus(pilot: Self.pilot(Self.queue), now: Self.now, nextLimit: 2)
        #expect(status.next.map(\.skillID) == [2, 3])
        #expect(status.remainingCount == 3)
    }

    @Test func progressCountsPointsTrainedBefore() {
        // Half the level was trained before; the other half goes over four hours.
        let partly = Self.entry(1, level: 4, start: -1, finish: 3, startPoints: 1500)
        let status = QueueStatus(pilot: Self.pilot([partly]), now: Self.now)
        #expect(status.current?.progress == 0.625)
    }

    @Test func endingSoonBoundary() {
        let queue = [Self.entry(1, level: 4, start: -1, finish: 24)]
        #expect(QueueStatus(pilot: Self.pilot(queue), now: Self.now).phase == .training)
        let later = Self.now.addingTimeInterval(1)
        #expect(QueueStatus(pilot: Self.pilot(queue), now: later).phase == .endingSoon)
    }

    @Test func finishedEntriesRollForward() {
        let pilot = Self.pilot(Self.queue)
        let after = QueueStatus(pilot: pilot, now: Self.now.addingTimeInterval(5 * Self.hour))
        #expect(after.current?.skillID == 2)
        #expect(after.next.map(\.skillID) == [3, 4])

        // The last entry under way: ending soon, nothing next.
        let last = QueueStatus(pilot: pilot, now: Self.now.addingTimeInterval(35 * Self.hour))
        #expect(last.current?.skillID == 4)
        #expect(last.current?.progress == 0.5)
        #expect(last.phase == .endingSoon)
        #expect(last.next.isEmpty)
        #expect(last.remainingCount == 0)
    }

    @Test func idleOnceEverythingFinished() {
        let status = QueueStatus(pilot: Self.pilot(Self.queue), now: Self.now.addingTimeInterval(41 * Self.hour))
        #expect(status.phase == .idle)
        #expect(status.current == nil)
        #expect(status.idleSince == Self.now.addingTimeInterval(40 * Self.hour))
    }

    @Test func emptyQueueIsIdleSinceTheLastFinishSeen() {
        let since = Self.now.addingTimeInterval(-52 * Self.hour)
        let status = QueueStatus(pilot: Self.pilot([], idleSince: since), now: Self.now)
        #expect(status.phase == .idle)
        #expect(status.idleSince == since)

        let unknown = QueueStatus(pilot: Self.pilot([]), now: Self.now)
        #expect(unknown.phase == .idle)
        #expect(unknown.idleSince == nil)
    }

    @Test func paused() {
        let queue = [Self.paused(1, level: 5, points: 1400), Self.paused(2, level: 5, points: 1000)]
        let status = QueueStatus(pilot: Self.pilot(queue), now: Self.now)
        #expect(status.phase == .paused)
        #expect(status.queueEnd == nil)
        #expect(status.current?.skillID == 1)
        #expect(status.current?.progress == 0.4)
        #expect(status.next.map(\.skillID) == [2])
        // Nothing moves while paused.
        let later = QueueStatus(pilot: Self.pilot(queue), now: Self.now.addingTimeInterval(100 * Self.hour))
        #expect(later.current?.progress == 0.4)
    }

    @Test func staleThreshold() {
        let justUnder = QueueStatus(pilot: Self.pilot(Self.queue, fetchedAgo: 23.99), now: Self.now)
        #expect(!justUnder.isStale)
        let atThreshold = QueueStatus(pilot: Self.pilot(Self.queue, fetchedAgo: 24), now: Self.now)
        #expect(atThreshold.isStale)
        #expect(atThreshold.fetchedAt == Self.now.addingTimeInterval(-24 * Self.hour))
        // Stale or not, the queue still counts down on its own dates.
        #expect(atThreshold.current?.skillID == 1)
    }

    @Test func noData() {
        let status = QueueStatus(pilot: WidgetSnapshot.Pilot(id: 1, name: "Nobody"), now: Self.now)
        #expect(status.phase == .noData)
        #expect(!status.isStale)
    }

    @Test func initials() {
        #expect(WidgetSnapshot.Pilot(id: 1, name: "Artem Valiant").initials == "AV")
        #expect(WidgetSnapshot.Pilot(id: 1, name: "Mira de la Quillfeather").initials == "MQ")
        #expect(WidgetSnapshot.Pilot(id: 1, name: "mono").initials == "M")
        #expect(WidgetSnapshot.Pilot(id: 1, name: "").initials == "")
    }

    // MARK: - Pilots

    private static let snapshot = WidgetSnapshot(activePilotID: 3, pilots: [
        pilot([], id: 1), pilot([], id: 2), pilot([], id: 3), pilot([], id: 4),
    ])

    @Test func singlePilot() {
        #expect(WidgetTimeline.pilot(in: Self.snapshot)?.id == 3)
        #expect(WidgetTimeline.pilot(in: Self.snapshot, selected: 2)?.id == 2)
        // Signed out since the widget was configured: the active pilot instead.
        #expect(WidgetTimeline.pilot(in: Self.snapshot, selected: 9)?.id == 3)
        #expect(WidgetTimeline.pilot(in: WidgetSnapshot(activePilotID: nil, pilots: [])) == nil)
    }

    @Test func multiPilotOrdering() {
        #expect(WidgetTimeline.pilots(in: Self.snapshot).map(\.id) == [3, 1, 2])
        #expect(WidgetTimeline.pilots(in: Self.snapshot, selected: [4, 9, 1, 4]).map(\.id) == [4, 1])
        #expect(WidgetTimeline.pilots(in: Self.snapshot, selected: []).map(\.id) == [3, 1, 2])
        let noActive = WidgetSnapshot(activePilotID: nil, pilots: Self.snapshot.pilots)
        #expect(WidgetTimeline.pilots(in: noActive, limit: 2).map(\.id) == [1, 2])
    }

    // MARK: - Timeline

    @Test func timelineDates() {
        let pilot = Self.pilot(Self.queue, fetchedAgo: 2)
        let dates = WidgetTimeline.dates(for: [pilot], from: Self.now, step: 3600, limit: 48)
        #expect(dates.first == Self.now)
        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
        #expect(dates.count == 48)
        // Every finish ahead, the start of "ending soon" and the moment it turns stale.
        for hours in [3.0, 10, 30, 40, 16, 22] {
            #expect(dates.contains(Self.now.addingTimeInterval(hours * Self.hour)))
        }
        // A finish already behind is not an entry.
        #expect(!dates.contains(Self.now.addingTimeInterval(-1 * Self.hour)))
    }

    @Test func timelineIsCapped() {
        let dates = WidgetTimeline.dates(for: [Self.pilot(Self.queue)], from: Self.now, step: 60, limit: 10)
        #expect(dates.count == 10)
        #expect(dates.last == Self.now.addingTimeInterval(9 * 60))
    }

    @Test func timelineWithoutData() {
        let dates = WidgetTimeline.dates(for: [WidgetSnapshot.Pilot(id: 1, name: "Nobody")], from: Self.now)
        #expect(dates == [Self.now])
    }

    // MARK: - File

    @Test func roundTripAndVersion() throws {
        let snapshot = WidgetSnapshot(activePilotID: 1, pilots: [Self.pilot(Self.queue)])
        let data = try #require(snapshot.encoded())
        #expect(WidgetSnapshot.decode(data) == snapshot)

        var other = snapshot
        other.version = WidgetSnapshot.currentVersion + 1
        #expect(WidgetSnapshot.decode(try #require(other.encoded())) == nil)
        #expect(WidgetSnapshot.decode(Data("{}".utf8)) == nil)
    }

    @Test func romanNumerals() {
        #expect((0...6).map(SkillLevelNumeral.roman) == ["0", "I", "II", "III", "IV", "V", "6"])
    }
}

private extension QueueStatus.Current {
    var skillID: Int64 { entry.skillID }
}
