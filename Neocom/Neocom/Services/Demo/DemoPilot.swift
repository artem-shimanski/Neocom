import DemoFixtures
import ESIKit
import Foundation
import os

/// The demo pilot: recorded, anonymised ESI responses bundled as `DemoFixtures.json`.
nonisolated enum DemoPilot {
    static let characterID = DemoIDs.characterID

    /// Whether the demo entry is offered: the app ships the demo data. Reads nothing.
    static var isAvailable: Bool { url != nil }

    /// The bundled archive, decoded once in the background; `nil` when the app ships without one
    /// or the file is unreadable.
    static func archive() async -> DemoArchive? {
        await loader.value
    }

    private static let url = Bundle.main.url(forResource: "DemoFixtures", withExtension: "json")

    private static let loader = Task.detached(priority: .userInitiated) { () -> DemoArchive? in
        guard let url else { return nil }
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
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Neocom", category: "Demo")
}
