import DogmaKit
import Foundation
import SwiftData

/// A player-owned fit: list-row metadata plus the whole fit as `FitDocument` JSON.
///
/// The fit is stored as one blob rather than a normalized graph, so CloudKit, which merges a
/// record whole, never combines parts of fits edited on different devices.
///
/// CloudKit-compatible: every property has a default, there are no unique constraints, and ids
/// are plain `Int`/`UUID`.
@Model
final class Fitting {
    /// Stable identity of the fit. Not `@Attribute(.unique)`: CloudKit does not support
    /// unique constraints.
    var uuid: UUID = UUID()
    var name: String = ""
    /// `TypeID.rawValue`, as `Int`: Core Data has no unsigned 32-bit type.
    var shipTypeID: Int = 0
    /// Uploaded to EVE as the fitting's description.
    var notes: String = ""
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast
    /// `FitDocument` JSON.
    var documentData: Data = Data()
    /// `FitDocument.version` at the time of writing. Diagnostics only.
    var documentVersion: Int = 0
    /// The in-game copy of this fit, if any. A UI hint only, never a source of truth.
    var esiFittingID: Int?
    var esiCharacterID: Int?

    init(uuid: UUID, name: String, shipTypeID: Int, notes: String, documentData: Data, documentVersion: Int) {
        self.uuid = uuid
        self.name = name
        self.shipTypeID = shipTypeID
        self.notes = notes
        self.documentData = documentData
        self.documentVersion = documentVersion
    }
}

/// A fitting list row, as a value so the list never holds a `@Model`.
struct FittingSummary: Sendable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var shipTypeID: TypeID
    var notes: String
    var updatedAt: Date
    var esiFittingID: Int64?
    var esiCharacterID: Int64?
}
