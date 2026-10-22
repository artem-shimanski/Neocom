//
//  SkillStanding.swift
//  TrainingKit
//

import SDEKit

/// Where one skill stands for a pilot: the state, the five level marks and the plan flag of a
/// skill row, derived from the pilot, the catalog and the local plan.
public struct SkillStanding: Sendable, Hashable {
    /// One state per skill, and every skill in exactly one of them.
    public enum State: Sendable, Hashable, CaseIterable {
        /// Injected and trained to V. Nothing left to do.
        case trainedToV
        /// Injected, below V, prerequisites met: the next level can go into the queue.
        case canTrain
        /// Not injected, prerequisites met: the book is all that is missing.
        case needsBook
        /// Prerequisites missing — `SkillStanding.missing` says which.
        case locked
    }

    /// What one segment of the level bar says about its level.
    public enum LevelMark: Sendable, Hashable {
        case trained
        /// The level the game is working on: the first entry of the queue.
        case training(paused: Bool)
        /// In the game queue behind the level in training.
        case queued
        /// In the local plan and nowhere in the game yet.
        case planned
        case empty
    }

    public var skillID: TypeID
    public var state: State
    /// `/skills` lists the skill, level 0 included.
    public var isInjected: Bool
    public var level: Int
    public var skillPoints: Int
    /// The direct prerequisites the pilot has not trained to the level asked for, in the
    /// catalog's order. Empty unless `state` is `locked`.
    public var missing: [SkillCatalog.Requirement]
    /// Levels I…V, in that order.
    public var marks: [LevelMark]

    /// Some level of the skill is in the game queue.
    public var isQueued: Bool {
        marks.contains { mark in
            switch mark {
            case .training, .queued: true
            default: false
            }
        }
    }

    /// The local plan takes the skill past what is trained, whether or not the game queue
    /// already holds those levels.
    public var isPlanned: Bool

    /// The level bar is shown for injected skills and for skills the plan or the queue holds.
    public var showsLevelBar: Bool {
        isInjected || isPlanned || isQueued
    }

    /// - Parameters:
    ///   - plannedLevel: the highest level of the skill the local plan reaches, 0 for none.
    ///     The plan holds an unbroken run of levels per skill.
    public init(skill: TypeID, pilot: Pilot, catalog: SkillCatalog, plannedLevel: Int) {
        let trained = pilot.skills[skill]
        let level = trained?.level ?? 0

        skillID = skill
        isInjected = trained != nil
        self.level = level
        skillPoints = trained?.skillPoints ?? 0

        missing = (catalog[skill]?.prerequisites ?? []).filter { requirement in
            pilot.trainedLevel(of: requirement.skillID) < requirement.level
        }

        if isInjected, level >= 5 {
            state = .trainedToV
        } else if !missing.isEmpty {
            state = .locked
        } else if isInjected {
            state = .canTrain
        } else {
            state = .needsBook
        }

        // `pilot.queue` holds unfinished entries by position; the first is the one in training,
        // paused when it has no dates.
        var queueMarks: [Int: LevelMark] = [:]
        for (index, entry) in pilot.queue.enumerated() where entry.skillID == skill {
            queueMarks[entry.finishedLevel] = index == 0
                ? .training(paused: entry.finishDate == nil)
                : .queued
        }

        marks = (1...5).map { segment in
            if segment <= level { return .trained }
            if let mark = queueMarks[segment] { return mark }
            if segment <= plannedLevel { return .planned }
            return .empty
        }
        isPlanned = plannedLevel > level
    }
}

/// The counts a group of skills — or all of them — carries on the Skills screen.
public struct SkillTally: Sendable, Hashable {
    public var total = 0
    /// Injected skills, level 0 included.
    public var injected = 0
    public var skillPoints: Int64 = 0
    public var trainedToV = 0
    public var canTrain = 0
    public var needsBook = 0
    public var locked = 0
    /// Skills with some level in the game queue.
    public var queued = 0
    /// Skills the local plan takes past what is trained.
    public var planned = 0
    /// What the game queue is doing among these skills: `training` when the level in training
    /// is one of theirs, `queued` when only later entries are, `nil` when none is.
    public var queueMark: SkillStanding.LevelMark?

    public init() {}

    public init(_ standings: some Sequence<SkillStanding>) {
        for standing in standings {
            add(standing)
        }
    }

    public mutating func add(_ standing: SkillStanding) {
        total += 1
        if standing.isInjected { injected += 1 }
        skillPoints += Int64(standing.skillPoints)
        switch standing.state {
        case .trainedToV: trainedToV += 1
        case .canTrain: canTrain += 1
        case .needsBook: needsBook += 1
        case .locked: locked += 1
        }
        if standing.isPlanned { planned += 1 }
        if standing.isQueued {
            queued += 1
            let training = standing.marks.first { if case .training = $0 { true } else { false } }
            if let training {
                queueMark = training
            } else if queueMark == nil {
                queueMark = .queued
            }
        }
    }

    public func count(of state: SkillStanding.State) -> Int {
        switch state {
        case .trainedToV: trainedToV
        case .canTrain: canTrain
        case .needsBook: needsBook
        case .locked: locked
        }
    }
}
