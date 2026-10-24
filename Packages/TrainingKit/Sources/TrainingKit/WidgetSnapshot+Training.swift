//
//  WidgetSnapshot+Training.swift
//  TrainingKit
//

import Foundation
import SDEKit
import TrainingTimeline

/// Conversion of a `CharacterSnapshot` and a plan into `WidgetSnapshot` values, with the names
/// and numbers that need the SDE filled in.
extension WidgetSnapshot.Training {
    /// - Parameters:
    ///   - catalog: supplies the level points ESI left out and the training time of a paused
    ///     entry; without it those fall back to what ESI sent, or to unknown.
    ///   - name: the skill's display name.
    ///   - previous: the snapshot written before, used for `idleSince` when the queue is empty.
    public init(snapshot: CharacterSnapshot, fetchedAt: Date, catalog: SkillCatalog?,
                previous: WidgetSnapshot.Training? = nil, name: (TypeID) -> String) {
        let records = Dictionary(snapshot.skills.map { ($0.skillID, $0) }, uniquingKeysWith: { first, _ in first })
        let attributes = snapshot.attributes
        var seen = Set<TypeID>()

        let queue = snapshot.queue.sorted { $0.position < $1.position }.map { entry in
            let skill = catalog?[entry.skillID]
            let bottom = entry.levelStartSkillPoints
                ?? skill.map { TrainingMath.skillPoints(rank: $0.rank, level: entry.finishedLevel - 1) } ?? 0
            let top = max(entry.levelEndSkillPoints
                ?? skill.map { TrainingMath.skillPoints(rank: $0.rank, level: entry.finishedLevel) } ?? bottom,
                bottom)

            // Only the first entry of a skill can start part of the way into its level: the
            // points `/skills` reports are the points before it.
            var start = bottom
            if seen.insert(entry.skillID).inserted, let record = records[entry.skillID],
               record.trainedLevel == entry.finishedLevel - 1 {
                start = min(max(record.skillPoints, bottom), top)
            }

            var duration: TimeInterval?
            if let startDate = entry.startDate, let finishDate = entry.finishDate {
                duration = finishDate.timeIntervalSince(startDate)
            } else if let skill {
                duration = TrainingMath.trainingTime(skillPoints: top - start,
                                                     primary: attributes[skill.primaryAttribute],
                                                     secondary: attributes[skill.secondaryAttribute])
            }

            return WidgetSnapshot.QueueEntry(skillID: Int64(entry.skillID.rawValue),
                                             name: name(entry.skillID),
                                             level: entry.finishedLevel,
                                             startDate: entry.startDate,
                                             finishDate: entry.finishDate,
                                             levelStartSkillPoints: bottom,
                                             levelEndSkillPoints: top,
                                             trainingStartSkillPoints: start,
                                             duration: duration)
        }

        // ESI drops finished entries on the next login, so an empty queue carries no finish date;
        // the last one seen before is used instead.
        var idleSince: Date?
        if queue.isEmpty, let previous {
            let lastFinish = previous.queue.compactMap(\.finishDate).max() ?? previous.idleSince
            idleSince = lastFinish.flatMap { $0 <= fetchedAt ? $0 : nil }
        }
        self.init(fetchedAt: fetchedAt, queue: queue, idleSince: idleSince)
    }
}

extension WidgetSnapshot.PlanEntry {
    /// The first `limit` levels of `plan` that `pilot` has yet to train, in plan order, with
    /// their training times.
    public static func entries(plan: [SkillCatalog.Requirement], pilot: Pilot, catalog: SkillCatalog,
                               limit: Int, name: (TypeID) -> String) -> [WidgetSnapshot.PlanEntry] {
        var queue = TrainingQueue(pilot: pilot, catalog: catalog)
        queue.add(requirements: plan)
        return queue.items.prefix(max(limit, 0)).map { item in
            WidgetSnapshot.PlanEntry(skillID: Int64(item.skillID.rawValue), name: name(item.skillID),
                                     level: item.targetLevel, duration: item.trainingTime)
        }
    }
}
