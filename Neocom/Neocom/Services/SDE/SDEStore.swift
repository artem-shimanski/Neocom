import Foundation
import LiteRow
import Observation
import SDEDataEN
import SDEDataMain
import SDEKit
import TrainingKit

/// The static EVE data export, opened once and shared by every screen.
///
/// The database is read-only; the states are not opened, open and failed. Only the attached
/// language file changes (`language`, `selectLanguage(_:)`). `@LiteQuery` keys its memory on the
/// database revision, so re-evaluated views read the new language; a view that stays on screen
/// across a switch keys its identity off `language`.
///
/// `skillCatalog` and `certificateCatalog` are built in the task that opens the database, so they
/// are present whenever the state is `.ready`.
///
/// Opening is deferred until a screen asks for it; the files are ~23 MB of mapped sqlite.
@MainActor
@Observable
final class SDEStore {
    enum State {
        case idle
        case loading
        case ready(SDEDatabase)
        case failed(any Error)
    }

    private(set) var state: State = .idle

    /// The skills and implant bonuses the training math reads, loaded with the database.
    /// `nil` unless the state is `.ready`.
    private(set) var skillCatalog: SkillCatalog?

    /// The certificate reference book, loaded with `skillCatalog`. `nil` unless the state is `.ready`.
    private(set) var certificateCatalog: CertificateCatalog?

    /// The language of the attached language file. English until the database is open or when the
    /// chosen file could not be used. The catalogs carry no text and are unaffected by a switch.
    private(set) var language: SDELanguage = .english

    /// The language being attached by `selectLanguage(_:)`.
    private(set) var switchingTo: SDELanguage?

    /// The most recently requested language while a switch is pending; earlier requests in
    /// between are skipped. `nil` when none.
    private(set) var requested: SDELanguage?

    /// The switch under way.
    private var switching: Task<Void, any Error>?

    /// The work of opening the files.
    ///
    /// Detached: `load()` is called from `.task`, and as a child task a cancelled screen would
    /// leave the store holding a `CancellationError`.
    private var opening: Task<Opened, any Error>?

    nonisolated private struct Opened: Sendable {
        var database: SDEDatabase
        var skills: SkillCatalog
        var certificates: CertificateCatalog
        var language: SDELanguage
        /// The chosen language's file failed to open, and English was opened instead.
        var fellBack: Bool
    }

    /// Opens the database unless already open. Safe to call repeatedly; a failed attempt is
    /// dropped and retried by the next call.
    func load() async {
        if case .ready = state { return }

        let task: Task<Opened, any Error>
        if let opening {
            task = opening
        } else {
            // The chosen language is tried first; if its file cannot be opened, the database opens
            // in English and English becomes the choice. The catalogs are built in the same
            // detached task.
            let preferred = Self.preferredLanguage
            task = Task.detached {
                var language = preferred
                var fellBack = false
                let opened: SDEDatabase
                do {
                    opened = try await SDEDatabase(main: SDEDataMain.url, text: preferred.fileURL)
                } catch where preferred != .english {
                    fellBack = true
                    language = .english
                    opened = try await SDEDatabase(main: SDEDataMain.url, text: SDEDataEN.url)
                }
                return Opened(database: opened,
                              skills: try await SkillCatalog(loading: opened),
                              certificates: try await CertificateCatalog(loading: opened),
                              language: language,
                              fellBack: fellBack)
            }
            opening = task
        }

        state = .loading
        switch await task.result {
        case let .success(opened):
            if opened.fellBack {
                Self.preferredLanguage = .english
            }
            skillCatalog = opened.skills
            certificateCatalog = opened.certificates
            language = opened.language
            state = .ready(opened.database)
        case let .failure(error):
            opening = nil
            state = .failed(error)
        }
    }

    /// Attaches `language` to the open database in place of the current one and makes it the
    /// choice. A file that fails to attach is thrown; the choice stays.
    ///
    /// A request made during another switch waits for it; one overtaken by a later request
    /// returns without effect. A completed switch rebuilds the scheduled notifications, which
    /// use the static data's language.
    func selectLanguage(_ language: SDELanguage) async throws {
        requested = language
        while let switching {
            _ = await switching.result
        }
        // A later request supersedes this one.
        guard requested == language else { return }
        requested = nil
        guard language != self.language else { return }
        guard case let .ready(database) = state else {
            // Nothing is attached yet; the next open picks the choice up.
            Self.preferredLanguage = language
            return
        }

        switchingTo = language
        let task = Task {
            try await database.setLanguage(text: language.fileURL)
            self.language = language
            Self.preferredLanguage = language
        }
        switching = task
        defer {
            switching = nil
            switchingTo = nil
        }
        try await task.value
        NotificationPlanner.shared.rescheduleAll(force: true)
        WidgetSnapshotWriter.shared.languageChanged()
    }

    // MARK: Preference

    private static let preferenceKey = "SDELanguage"

    /// The language the player chose, or English. Read once per open.
    private static var preferredLanguage: SDELanguage {
        get { UserDefaults.standard.string(forKey: preferenceKey).flatMap(SDELanguage.code) ?? .english }
        set {
            if newValue == .english {
                UserDefaults.standard.removeObject(forKey: preferenceKey)
            } else {
                UserDefaults.standard.set(newValue.code, forKey: preferenceKey)
            }
        }
    }

    // MARK: Cleanup

    /// Deletes the language files downloaded by earlier versions into `Application Support/SDE/`,
    /// with their temporary files. Best effort, off the main thread.
    nonisolated static func removeDownloadedLanguages() {
        Task.detached(priority: .background) {
            let manager = FileManager.default
            let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SDE", isDirectory: true)
            for directory in [support, manager.temporaryDirectory] {
                let names = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
                for name in names where name.hasPrefix("text-") && name.hasSuffix(".sqlite") {
                    try? manager.removeItem(at: directory.appendingPathComponent(name))
                }
            }
            if (try? manager.contentsOfDirectory(atPath: support.path))?.isEmpty == true {
                try? manager.removeItem(at: support)
            }
        }
    }
}
