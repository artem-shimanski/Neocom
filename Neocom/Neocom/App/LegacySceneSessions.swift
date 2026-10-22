import Foundation
import os

/// Clears scene sessions left in the saved application state by a previous App Store version.
/// Such a session names the "Default Configuration" scene configuration, which this app does not
/// declare, so UIKit connects the scene without a delegate and the screen stays black. A session
/// cannot be destroyed on iPhone, so the saved state is removed before UIKit reads it.
enum LegacySceneSessions {
    private static let legacyConfigurationName = "Default Configuration"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Neocom",
                                       category: "Scenes")

    /// Removes the saved state when a known session carries the legacy configuration; does nothing
    /// otherwise or on failure.
    static func discardIfNeeded() {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else { return }
        let state = library
            .appendingPathComponent("Saved Application State", isDirectory: true)
            .appendingPathComponent("\(bundleID).savedState", isDirectory: true)
        let file = state
            .appendingPathComponent("KnownSceneSessions", isDirectory: true)
            .appendingPathComponent("data.data")
        guard let data = try? Data(contentsOf: file),
              let sessions = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Data]
        else { return }

        // Only the archive's string table is read; unarchiving a `UISceneSession` this early needs UIKit.
        let isLegacy = sessions.values.contains { archive in
            guard let plist = try? PropertyListSerialization.propertyList(from: archive, format: nil) as? [String: Any],
                  let objects = plist["$objects"] as? [Any]
            else { return false }
            return objects.contains { ($0 as? String) == legacyConfigurationName }
        }
        guard isLegacy else { return }

        do {
            try FileManager.default.removeItem(at: state)
            logger.notice("Discarded saved scene sessions of a previous version")
        } catch {
            logger.error("Could not discard saved scene sessions: \(error.localizedDescription)")
        }
    }
}
