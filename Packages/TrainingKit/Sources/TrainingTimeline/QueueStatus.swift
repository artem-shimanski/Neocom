//
//  QueueStatus.swift
//  TrainingTimeline
//

import Foundation

/// Where one pilot's queue stands at a given moment, worked out from the snapshot alone.
///
/// Entries whose finish date has passed count as trained; the first one ahead is the current
/// skill, and its progress is where its points are at `now`.
public struct QueueStatus: Sendable, Hashable {
    /// How long before the queue runs out it is reported as ending soon.
    public static let endingSoonWithin: TimeInterval = 24 * 3600
    /// How old the snapshot may get before the widget says how old it is.
    public static let staleAfter: TimeInterval = 24 * 3600

    public enum Phase: Sendable, Hashable {
        /// Training, the queue ends at `queueEnd`, more than `endingSoonWithin` away.
        case training
        /// Training, and the queue ends within `endingSoonWithin`.
        case endingSoon
        /// Entries ahead but no dates: ESI reports a paused queue that way.
        case paused
        /// Nothing ahead — the queue is empty or every entry has finished.
        case idle
        /// The app has fetched nothing for this pilot yet.
        case noData
    }

    /// The skill being trained (or paused) right now.
    public struct Current: Sendable, Hashable {
        public var entry: WidgetSnapshot.QueueEntry
        /// Points in the skill at `now`.
        public var skillPoints: Int
        /// How far into `entry.level` the skill is, by points: 0...1.
        public var progress: Double

        public var name: String { entry.name }
        public var level: Int { entry.level }
        /// The levels already trained — the filled part of the level bar.
        public var trainedLevel: Int { max(entry.level - 1, 0) }
    }

    public var phase: Phase
    public var current: Current?
    /// The entries after `current`, at most the `nextLimit` asked for.
    public var next: [WidgetSnapshot.QueueEntry]
    /// Every entry after `current`, not only those in `next`.
    public var remainingCount: Int
    /// When the last entry finishes; set while training.
    public var queueEnd: Date?
    /// When training stopped; set when idle and known.
    public var idleSince: Date?
    /// When the snapshot was fetched; `nil` without data.
    public var fetchedAt: Date?
    /// The snapshot is older than `staleAfter`.
    public var isStale: Bool

    public init(pilot: WidgetSnapshot.Pilot, now: Date, nextLimit: Int = 3) {
        guard let training = pilot.training else {
            self.init(phase: .noData, current: nil, next: [], remainingCount: 0, queueEnd: nil,
                      idleSince: nil, fetchedAt: nil, isStale: false)
            return
        }
        let isStale = now.timeIntervalSince(training.fetchedAt) >= Self.staleAfter
        // An entry without a finish date is paused and always ahead.
        let ahead = training.queue.filter { entry in entry.finishDate.map { $0 > now } ?? true }

        guard let first = ahead.first else {
            let lastFinish = training.queue.compactMap(\.finishDate).max()
            self.init(phase: .idle, current: nil, next: [], remainingCount: 0, queueEnd: nil,
                      idleSince: lastFinish ?? training.idleSince, fetchedAt: training.fetchedAt,
                      isStale: isStale)
            return
        }

        let rest = Array(ahead.dropFirst())
        let current = Current(entry: first, now: now)
        let queueEnd = ahead.compactMap(\.finishDate).max()
        let phase: Phase
        if let queueEnd {
            phase = queueEnd.timeIntervalSince(now) < Self.endingSoonWithin ? .endingSoon : .training
        } else {
            phase = .paused
        }
        self.init(phase: phase, current: current, next: Array(rest.prefix(max(nextLimit, 0))),
                  remainingCount: rest.count, queueEnd: queueEnd, idleSince: nil,
                  fetchedAt: training.fetchedAt, isStale: isStale)
    }

    public init(phase: Phase, current: Current?, next: [WidgetSnapshot.QueueEntry], remainingCount: Int,
                queueEnd: Date?, idleSince: Date?, fetchedAt: Date?, isStale: Bool) {
        self.phase = phase
        self.current = current
        self.next = next
        self.remainingCount = remainingCount
        self.queueEnd = queueEnd
        self.idleSince = idleSince
        self.fetchedAt = fetchedAt
        self.isStale = isStale
    }
}

extension QueueStatus.Current {
    /// Points move linearly from `trainingStartSkillPoints` at the start to the top of the level
    /// at the finish; a paused entry stays where it is.
    init(entry: WidgetSnapshot.QueueEntry, now: Date) {
        let bottom = entry.levelStartSkillPoints
        let top = max(entry.levelEndSkillPoints, bottom)
        let start = min(max(entry.trainingStartSkillPoints, bottom), top)

        var fraction: Double?
        if let startDate = entry.startDate, let finishDate = entry.finishDate {
            let duration = finishDate.timeIntervalSince(startDate)
            fraction = duration > 0 ? min(max(now.timeIntervalSince(startDate) / duration, 0), 1) : 1
        }
        let points = Double(start) + Double(top - start) * (fraction ?? 0)

        self.entry = entry
        skillPoints = Int(points.rounded(.down))
        if top > bottom {
            progress = min(max((points - Double(bottom)) / Double(top - bottom), 0), 1)
        } else {
            // No point range: progress follows time.
            progress = fraction ?? 0
        }
    }
}
