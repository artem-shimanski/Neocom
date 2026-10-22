import DemoFixtures
import ESIKit
import Foundation
import os

/// The demo pilot: recorded, anonymised ESI responses bundled as `DemoFixtures.json`.
nonisolated enum DemoPilot {
    static let characterID = DemoIDs.characterID

    /// The bundled archive, decoded on first use; `nil` when the app ships without one.
    static let archive: DemoArchive? = {
        guard let url = Bundle.main.url(forResource: "DemoFixtures", withExtension: "json") else { return nil }
        do {
            let archive = try DemoArchive.decode(from: Data(contentsOf: url))
            #if DEBUG
            if archive.compatibilityDate != ESIConfiguration.defaultCompatibilityDate {
                log.error("Demo fixtures recorded for \(archive.compatibilityDate, privacy: .public), ESIKit uses \(ESIConfiguration.defaultCompatibilityDate, privacy: .public)")
            }
            #endif
            return archive
        } catch {
            log.error("Demo fixtures unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    /// Whether the demo entry is offered.
    static var isAvailable: Bool { archive != nil }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Neocom", category: "Demo")
}
