import Foundation
import Observation
import SDEKit
import SwiftData
import TrainingKit

/// One character's local training plan: skill levels in training order.
///
/// A facade over `ModelContext` that exposes only `SkillCatalog.Requirement` values, never a
/// `@Model`. Separate from the in-game skill queue, which ESI cannot write.
@Observable
@MainActor
final class TrainingPlanStore {
    /// The plan in training order, updated by every mutating call.
    private(set) var entries: [SkillCatalog.Requirement] = []

    @ObservationIgnored private let context: ModelContext
    /// `Int`, matching `TrainingPlanEntry.characterID` in predicates.
    @ObservationIgnored private let characterID: Int

    init(context: ModelContext, characterID: Int64) {
        self.context = context
        self.characterID = Int(characterID)
        reload()
    }

    // MARK: - Reading

    func contains(skill: TypeID, level: Int) -> Bool {
        entries.contains(SkillCatalog.Requirement(skillID: skill, level: level))
    }

    // MARK: - Editing

    /// Appends the requirements not yet in the plan, in the given order.
    ///
    /// Deduplicates by (skill, level) here, since CloudKit does not support
    /// `@Attribute(.unique)`. Each level of a skill is a separate entry.
    func add(_ requirements: [SkillCatalog.Requirement]) {
        let stored = fetch()
        var known = Set(stored.map(Self.requirement(of:)))
        var position = (stored.map(\.position).max() ?? -1) + 1

        for requirement in requirements {
            // Skips duplicates both in the plan and within `requirements`.
            guard known.insert(requirement).inserted else { continue }
            context.insert(TrainingPlanEntry(characterID: characterID,
                                             skillID: Int(requirement.skillID.rawValue),
                                             level: requirement.level,
                                             position: position))
            position += 1
        }
        save()
    }

    /// Removes every level of `skill` from the plan.
    func remove(skill: TypeID) {
        let skillID = Int(skill.rawValue)
        for entry in fetch() where entry.skillID == skillID {
            context.delete(entry)
        }
        renumber()
        save()
    }

    /// Removes the levels of `skill` above `level`.
    func trim(skill: TypeID, toLevel level: Int) {
        let skillID = Int(skill.rawValue)
        for entry in fetch() where entry.skillID == skillID && entry.level > level {
            context.delete(entry)
        }
        renumber()
        save()
    }

    func clear() {
        for entry in fetch() {
            context.delete(entry)
        }
        save()
    }

    // MARK: - Storage

    /// The character's entries in training order, from the shared app-wide context.
    private func fetch() -> [TrainingPlanEntry] {
        let characterID = characterID
        let descriptor = FetchDescriptor<TrainingPlanEntry>(
            predicate: #Predicate { $0.characterID == characterID },
            sortBy: [SortDescriptor(\.position)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Keeps `position` a dense 0-based order after removals.
    private func renumber() {
        for (index, entry) in fetch().enumerated() where entry.position != index {
            entry.position = index
        }
    }

    /// Saves explicitly (not via autosave) so the next fetch sees the changes, then refreshes
    /// ``entries``.
    private func save() {
        try? context.save()
        reload()
        // The empty-queue widget shows the head of the plan.
        WidgetSnapshotWriter.shared.setNeedsUpdate()
    }

    private func reload() {
        entries = fetch().map(Self.requirement(of:))
    }

    private static func requirement(of entry: TrainingPlanEntry) -> SkillCatalog.Requirement {
        SkillCatalog.Requirement(skillID: TypeID(rawValue: UInt32(clamping: entry.skillID)),
                                 level: entry.level)
    }
}
