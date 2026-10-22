import DogmaKit
import Foundation
import LegacyImportKit
import os

/// One-time import of fits from the legacy Neocom Core Data store (`cloud.sqlite` in
/// Application Support). The legacy store is read from a copy and never modified.
enum LegacyFitsImport {
    private static let doneKey = "legacyFitsImportDone"
    nonisolated private static let log = Logger(subsystem: "com.shimanski.neocom", category: "LegacyFitsImport")

    /// Reads and converts off the main actor, then inserts through `store`. Marked done only
    /// after a pass that read the store or found none, so a failure is retried on the next
    /// launch; unreadable fits are skipped.
    @MainActor
    static func runIfNeeded(into store: FittingStore) async {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        let fits: [FittingStore.Imported]
        do {
            let level = FitDocument.assumedSkillLevel
            fits = try await Task.detached(priority: .utility) { try read(skillLevel: level) }.value
        } catch {
            log.error("Old fits not imported: \(String(describing: error), privacy: .public)")
            return
        }
        let inserted = store.insert(fits)
        if !fits.isEmpty {
            log.info("Old fits: \(inserted) imported, \(fits.count - inserted) already present")
        }
        UserDefaults.standard.set(true, forKey: doneKey)
    }

    nonisolated private static func read(skillLevel: UInt8) throws -> [FittingStore.Imported] {
        let url = URL.applicationSupportDirectory.appendingPathComponent("cloud.sqlite")
        guard let contents = try LegacyFitStore.read(at: url) else { return [] }
        for failure in contents.failures {
            log.error("Old fit skipped: \(failure, privacy: .public)")
        }
        return contents.fits.map { fit in
            // Legacy fits are often unnamed.
            let name = fit.name.isEmpty ? String(localized: "New Fit") : fit.name
            return FittingStore.Imported(id: fit.uuid,
                                         shipTypeID: TypeID(rawValue: UInt32(clamping: fit.ship.typeID)),
                                         name: name,
                                         document: fit.ship.fitDocument(name: name,
                                                                        skillLevel: skillLevel))
        }
    }
}
