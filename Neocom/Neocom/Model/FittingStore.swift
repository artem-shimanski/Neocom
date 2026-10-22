import CoreData
import DogmaKit
import Foundation
import Observation
import SwiftData

/// The player's own fits.
///
/// A facade over `ModelContext` that never exposes a `@Model`; every mutating call stamps
/// `updatedAt` and saves explicitly.
///
/// Also holds drafts: fits open in the editor but not yet stored, kept in memory only. Reads
/// and writes treat a draft like a record under its id. The first write (`save`, `rename`,
/// `setNotes`) or `persist` inserts the record under the same id; `discardDraft` drops it.
@Observable
@MainActor
final class FittingStore {
    /// All stored fits, most recently changed first.
    private(set) var fits: [FittingSummary] = []

    /// Drafts, not included in ``fits``. Observed, so views see a draft become a record.
    private var draftsByID: [UUID: Draft] = [:]

    private struct Draft {
        var shipTypeID: TypeID
        var name: String
        var notes: String
        var document: FitDocument
        var createdAt: Date
    }

    @ObservationIgnored private let context: ModelContext
    /// Block-based `NotificationCenter` observers, removed in `deinit`.
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(context: ModelContext) {
        self.context = context
        reload()
        observeChangesFromElsewhere()
    }

    deinit {
        // Not actor-isolated, but `NotificationCenter` is thread-safe.
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Reading

    func summary(of id: UUID) -> FittingSummary? {
        if let draft = draftsByID[id] { return Self.summary(of: draft, id: id) }
        return fetch(id).map(Self.summary(of:))
    }

    var drafts: [FittingSummary] {
        draftsByID.map { Self.summary(of: $1, id: $0) }
    }

    func isDraft(_ id: UUID) -> Bool {
        draftsByID[id] != nil
    }

    /// `nil` when the record is gone or its document cannot be decoded; an undecodable record
    /// stays in the list.
    func document(of id: UUID) -> FitDocument? {
        if let draft = draftsByID[id] { return draft.document }
        guard let entity = fetch(id) else { return nil }
        return try? JSONDecoder().decode(FitDocument.self, from: entity.documentData)
    }

    // MARK: - Editing

    /// Stores a new fit; `createdAt` and `updatedAt` are set to now.
    @discardableResult
    func create(shipTypeID: TypeID, name: String, document: FitDocument, notes: String = "") -> UUID {
        var document = document
        document.name = name
        let data = (try? JSONEncoder().encode(document)) ?? Data()
        let now = Date()
        let entity = Fitting(uuid: UUID(),
                             name: name,
                             shipTypeID: Int(shipTypeID.rawValue),
                             notes: notes,
                             documentData: data,
                             documentVersion: document.version)
        entity.createdAt = now
        entity.updatedAt = now
        context.insert(entity)
        save()
        return entity.uuid
    }

    /// A fit imported with its own id, e.g. from the legacy app.
    nonisolated struct Imported: Sendable {
        var id: UUID
        var shipTypeID: TypeID
        var name: String
        var document: FitDocument
    }

    /// Inserts the fits whose ids are not stored yet (another device may have synced them), in
    /// one save. Returns the number inserted.
    @discardableResult
    func insert(_ fits: [Imported]) -> Int {
        var stored = Set(((try? context.fetch(FetchDescriptor<Fitting>())) ?? []).map(\.uuid))
        let now = Date()
        var inserted = 0
        for fit in fits where stored.insert(fit.id).inserted {
            var document = fit.document
            document.name = fit.name
            let entity = Fitting(uuid: fit.id,
                                 name: fit.name,
                                 shipTypeID: Int(fit.shipTypeID.rawValue),
                                 notes: "",
                                 documentData: (try? JSONEncoder().encode(document)) ?? Data(),
                                 documentVersion: document.version)
            entity.createdAt = now
            entity.updatedAt = now
            context.insert(entity)
            inserted += 1
        }
        if inserted > 0 { save() }
        return inserted
    }

    /// Creates a draft, stored only once it is changed or persisted.
    func createDraft(shipTypeID: TypeID, name: String, document: FitDocument, notes: String = "") -> UUID {
        var document = document
        document.name = name
        let id = UUID()
        draftsByID[id] = Draft(shipTypeID: shipTypeID, name: name, notes: notes,
                               document: document, createdAt: .now)
        return id
    }

    /// Stores a draft as a record under its id; no-op for a non-draft id.
    func persist(_ id: UUID) {
        guard promote(id) != nil else { return }
        save()
    }

    /// Drops a draft without storing it; no-op for a non-draft id.
    func discardDraft(_ id: UUID) {
        draftsByID[id] = nil
    }

    /// Stores `document`, overriding `document.name` with the record's `name`, which is the
    /// source of truth. Persists a draft.
    func save(_ document: FitDocument, to id: UUID) {
        guard let entity = promote(id) ?? fetch(id) else { return }
        var document = document
        document.name = entity.name
        guard let data = try? JSONEncoder().encode(document) else { return }
        entity.documentData = data
        entity.documentVersion = document.version
        entity.updatedAt = .now
        save()
    }

    /// Renames both the record and the embedded document; an undecodable document does not
    /// block the rename.
    func rename(_ id: UUID, to name: String) {
        guard let entity = promote(id) ?? fetch(id) else { return }
        entity.name = name
        entity.documentData = Self.documentData(entity.documentData, named: name)
        entity.updatedAt = .now
        save()
    }

    func setNotes(_ notes: String, of id: UUID) {
        guard let entity = promote(id) ?? fetch(id) else { return }
        entity.notes = notes
        entity.updatedAt = .now
        save()
    }

    /// Copies a fit as `"<name> copy"`. The link to the in-game fitting is not copied.
    @discardableResult
    func duplicate(_ id: UUID) -> UUID? {
        guard let entity = fetch(id) else { return nil }
        let name = "\(entity.name) copy"
        let now = Date()
        let copy = Fitting(uuid: UUID(),
                           name: name,
                           shipTypeID: entity.shipTypeID,
                           notes: entity.notes,
                           documentData: Self.documentData(entity.documentData, named: name),
                           documentVersion: entity.documentVersion)
        copy.createdAt = now
        copy.updatedAt = now
        context.insert(copy)
        save()
        return copy.uuid
    }

    /// Deletes a record, or drops a draft.
    func delete(_ id: UUID) {
        if draftsByID.removeValue(forKey: id) != nil { return }
        guard let entity = fetch(id) else { return }
        context.delete(entity)
        save()
    }

    func link(_ id: UUID, esiFittingID: Int64?, characterID: Int64?) {
        guard let entity = fetch(id) else { return }
        entity.esiFittingID = esiFittingID.map(Int.init)
        entity.esiCharacterID = characterID.map(Int.init)
        entity.updatedAt = .now
        save()
    }

    func reload() {
        fits = fetchAll().map(Self.summary(of:))
    }

    // MARK: - External changes

    /// Reloads ``fits`` on saves from other contexts (`ModelContext.didSave`) and on remote
    /// store changes, e.g. from iCloud (`.NSPersistentStoreRemoteChange`).
    private func observeChangesFromElsewhere() {
        let names: [Notification.Name] = [.NSPersistentStoreRemoteChange, ModelContext.didSave]
        observers = names.map { name in
            // `weak self` here: the store owns the tokens, so a strong capture is a cycle.
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                // The sender is reduced to a `Sendable` identity before entering the main actor.
                let sender = (notification.object as? ModelContext).map(ObjectIdentifier.init)
                // `queue: .main` delivers on the main thread, so the assumption holds.
                MainActor.assumeIsolated {
                    self?.reload(unlessSavedBy: sender)
                }
            }
        }
    }

    /// Skips notifications from this store's own context, whose `save()` has already reloaded.
    private func reload(unlessSavedBy sender: ObjectIdentifier?) {
        guard sender != ObjectIdentifier(context) else { return }
        reload()
    }

    // MARK: - Storage

    private func fetchAll() -> [Fitting] {
        let descriptor = FetchDescriptor<Fitting>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Inserts a draft as a record under its id and removes the draft; the caller saves.
    /// `nil` when `id` is not a draft.
    private func promote(_ id: UUID) -> Fitting? {
        guard let draft = draftsByID.removeValue(forKey: id) else { return nil }
        let entity = Fitting(uuid: id,
                             name: draft.name,
                             shipTypeID: Int(draft.shipTypeID.rawValue),
                             notes: draft.notes,
                             documentData: (try? JSONEncoder().encode(draft.document)) ?? Data(),
                             documentVersion: draft.document.version)
        entity.createdAt = draft.createdAt
        entity.updatedAt = .now
        context.insert(entity)
        return entity
    }

    private func fetch(_ id: UUID) -> Fitting? {
        let descriptor = FetchDescriptor<Fitting>(predicate: #Predicate { $0.uuid == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// Saves the pending changes and refreshes ``fits``.
    private func save() {
        try? context.save()
        reload()
    }

    /// The document blob with `name` written into it; returned unchanged if it cannot be
    /// decoded or re-encoded.
    private static func documentData(_ data: Data, named name: String) -> Data {
        guard var document = try? JSONDecoder().decode(FitDocument.self, from: data) else { return data }
        document.name = name
        return (try? JSONEncoder().encode(document)) ?? data
    }

    private static func summary(of entity: Fitting) -> FittingSummary {
        FittingSummary(id: entity.uuid,
                       name: entity.name,
                       shipTypeID: TypeID(rawValue: UInt32(clamping: entity.shipTypeID)),
                       notes: entity.notes,
                       updatedAt: entity.updatedAt,
                       esiFittingID: entity.esiFittingID.map(Int64.init),
                       esiCharacterID: entity.esiCharacterID.map(Int64.init))
    }

    private static func summary(of draft: Draft, id: UUID) -> FittingSummary {
        FittingSummary(id: id,
                       name: draft.name,
                       shipTypeID: draft.shipTypeID,
                       notes: draft.notes,
                       updatedAt: draft.createdAt,
                       esiFittingID: nil,
                       esiCharacterID: nil)
    }
}

// MARK: - In-game fittings

extension FittingStore {
    /// Opens an in-game fitting (or a killmail's lost fit) as an unlinked draft. `warnings`
    /// lists what the conversion could not carry over.
    func createDraft(from fitting: ESIFitting, catalog: TypeCatalog) -> (id: UUID, warnings: [String]) {
        var warnings: [String] = []
        let document = FitDocument(fitting, catalog: catalog, warnings: &warnings)
        let id = createDraft(shipTypeID: TypeID(rawValue: UInt32(clamping: fitting.shipTypeID)),
                             name: fitting.name,
                             document: document,
                             notes: fitting.fittingDescription)
        return (id, warnings)
    }
}
