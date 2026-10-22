import Foundation
import SwiftData

/// One skill level in a player's training plan.
///
/// CloudKit-compatible: every property has a default, there are no unique constraints, and ids
/// are plain `Int`.
@Model
final class TrainingPlanEntry {
    var characterID: Int = 0
    /// `TypeID.rawValue`, as `Int`: Core Data has no unsigned 32-bit type.
    var skillID: Int = 0
    var level: Int = 0
    var position: Int = 0
    var addedAt: Date = Date.distantPast

    init(characterID: Int, skillID: Int, level: Int, position: Int) {
        self.characterID = characterID
        self.skillID = skillID
        self.level = level
        self.position = position
        self.addedAt = Date()
    }
}
