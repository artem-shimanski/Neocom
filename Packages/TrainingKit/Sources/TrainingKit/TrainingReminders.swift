//
//  TrainingReminders.swift
//  TrainingKit
//

import Foundation
import SDEKit

/// One local notification the skill queue calls for: a skill reaching its level, or the queue
/// about to run dry. Plain data — the app puts it into words and hands it to iOS.
public struct TrainingReminder: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// `skillID` reaches `level` at `eventDate`.
        case skillTrained(skillID: TypeID, level: Int)
        /// The last skill in the queue, `skillID` to `level`, ends at `eventDate`;
        /// `leadHours` before it is when the reminder goes off.
        case queueEnding(skillID: TypeID, level: Int, leadHours: Int)
    }

    /// Stable for the same event, so rescheduling replaces the pending notification.
    public var id: String
    public var kind: Kind
    /// When the notification goes off: the event, less the lead.
    public var fireDate: Date
    public var eventDate: Date

    public init(id: String, kind: Kind, fireDate: Date, eventDate: Date) {
        self.id = id
        self.kind = kind
        self.fireDate = fireDate
        self.eventDate = eventDate
    }
}

public enum TrainingReminders {
    /// What the "queue running out" lead can be, in hours: the moment itself, or so long before.
    public static let leadChoices: [Int] = [0, 1, 12, 24, 48]
    public static let defaultLead = 12

    /// Every reminder `queue` calls for, soonest first.
    ///
    /// Only entries with a finish date count, so a paused queue yields none. Reminders whose
    /// moment has passed are left out, including a "queue running out" whose lead window has
    /// already begun.
    public static func plan(queue: [CharacterSnapshot.QueueEntry],
                            skillTrained: Bool,
                            queueEnding: Bool,
                            leadHours: Int,
                            now: Date) -> [TrainingReminder] {
        let timed = queue
            .compactMap { entry in entry.finishDate.map { (entry, $0) } }
            .filter { $0.1 > now }
            .sorted { ($0.1, $0.0.position) < ($1.1, $1.0.position) }

        var reminders: [TrainingReminder] = []
        if skillTrained {
            for (entry, finish) in timed {
                reminders.append(TrainingReminder(
                    id: "skill.\(entry.skillID.rawValue).\(entry.finishedLevel)",
                    kind: .skillTrained(skillID: entry.skillID, level: entry.finishedLevel),
                    fireDate: finish, eventDate: finish))
            }
        }
        if queueEnding, let (last, end) = timed.last {
            let lead = max(0, leadHours)
            let fire = end.addingTimeInterval(-TimeInterval(lead) * 3600)
            if fire > now {
                reminders.append(TrainingReminder(
                    id: "queue-end",
                    kind: .queueEnding(skillID: last.skillID, level: last.finishedLevel, leadHours: lead),
                    fireDate: fire, eventDate: end))
            }
        }
        return reminders.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    }

    /// Where a pilot's queue stands for the notifications screen: training until a moment,
    /// paused, or empty.
    public enum QueueState: Sendable, Hashable {
        case empty
        case paused
        case training(until: Date)
    }

    public static func state(of queue: [CharacterSnapshot.QueueEntry], now: Date) -> QueueState {
        let ahead = queue.filter { entry in entry.finishDate.map { $0 > now } ?? true }
        if ahead.isEmpty { return .empty }
        let finishes = ahead.compactMap(\.finishDate)
        guard let end = finishes.max() else { return .paused }
        return .training(until: end)
    }
}
