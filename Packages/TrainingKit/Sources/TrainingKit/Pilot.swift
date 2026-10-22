//
//  Pilot.swift
//  TrainingKit
//

import Foundation
import SDEKit

/// A `CharacterSnapshot` with the three corrections ESI leaves to the client applied in `init`.
public struct Pilot: Sendable {
    /// The level reached and the skill points behind it.
    public struct TrainedSkill: Sendable, Hashable {
        public var level: Int
        public var skillPoints: Int

        public init(level: Int, skillPoints: Int) {
            self.level = level
            self.skillPoints = skillPoints
        }
    }

    /// Attributes without implants.
    public var baseAttributes: CharacterAttributes
    /// Sum of the worn implants' bonuses.
    public var implantBonus: CharacterAttributes
    /// Base plus implants; the input of every training time calculation.
    public var attributes: CharacterAttributes
    public var skills: [TypeID: TrainedSkill]
    /// The future of the queue only, by ascending position.
    public var queue: [CharacterSnapshot.QueueEntry]
    public var totalSkillPoints: Int64

    public init(snapshot: CharacterSnapshot, catalog: SkillCatalog, now: Date = .now) {
        baseAttributes = snapshot.attributes
        // Rule 1: ESI attributes exclude implants; the bonus comes from the catalog.
        implantBonus = catalog.attributes(ofImplants: snapshot.implants)
        attributes = baseAttributes + implantBonus
        totalSkillPoints = snapshot.totalSkillPoints

        var skills: [TypeID: TrainedSkill] = [:]
        for record in snapshot.skills {
            skills[record.skillID] = TrainedSkill(level: record.trainedLevel,
                                                  skillPoints: record.skillPoints)
        }

        /// Raises a skill to what the queue proves it has reached; never lowers anything.
        func credit(_ skillID: TypeID, level: Int, skillPoints: Int) {
            let known = skills[skillID]
            skills[skillID] = TrainedSkill(level: max(known?.level ?? 0, level),
                                           skillPoints: max(known?.skillPoints ?? 0, skillPoints))
        }

        /// Points at the end of `level`: the reported value, else from the catalog's rank;
        /// `nil` when the skill is not in the catalog.
        func skillPoints(_ skillID: TypeID, level: Int, reported: Int?) -> Int? {
            if let reported { return reported }
            guard let rank = catalog[skillID]?.rank else { return nil }
            return TrainingMath.skillPoints(rank: rank, level: level)
        }

        var future: [CharacterSnapshot.QueueEntry] = []

        for entry in snapshot.queue.sorted(by: { $0.position < $1.position }) {
            // A paused queue has no dates: the entry is skipped by rules 2 and 3 but stays in
            // `queue`.
            guard let startDate = entry.startDate, let finishDate = entry.finishDate else {
                future.append(entry)
                continue
            }

            guard finishDate > now else {
                // Rule 2: a finished entry is credited; `/skills` catches up on the next login.
                if let endPoints = skillPoints(entry.skillID, level: entry.finishedLevel,
                                               reported: entry.levelEndSkillPoints) {
                    credit(entry.skillID, level: entry.finishedLevel, skillPoints: endPoints)
                }
                continue
            }

            future.append(entry)

            // Rule 3: the entry in training keeps the level at `finishedLevel - 1`; only the
            // points advance by the fraction trained so far.
            guard startDate < now,
                  let startPoints = skillPoints(entry.skillID, level: entry.finishedLevel - 1,
                                                reported: entry.levelStartSkillPoints),
                  let endPoints = skillPoints(entry.skillID, level: entry.finishedLevel,
                                              reported: entry.levelEndSkillPoints)
            else { continue }

            // Guards against a zero duration from corrupted dates.
            let duration = finishDate.timeIntervalSince(startDate)
            let progress = duration > 0
                ? min(max(now.timeIntervalSince(startDate) / duration, 0), 1)
                : 1
            let points = Double(startPoints) + Double(endPoints - startPoints) * progress

            credit(entry.skillID, level: max(entry.finishedLevel - 1, 0),
                   skillPoints: Int(points.rounded()))
        }

        self.skills = skills
        self.queue = future
    }

    /// The trained level of a skill, 0 when it is not trained.
    public func trainedLevel(of skill: TypeID) -> Int {
        skills[skill]?.level ?? 0
    }

    public func skillPoints(in skill: TypeID) -> Int {
        skills[skill]?.skillPoints ?? 0
    }
}
