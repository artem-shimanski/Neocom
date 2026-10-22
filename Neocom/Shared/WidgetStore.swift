import Foundation
import TrainingTimeline

/// The kinds of the widgets, for `StaticConfiguration`/`AppIntentConfiguration` in the extension
/// and for the app's reload after it writes a new snapshot.
nonisolated enum WidgetKind {
    /// One pilot's queue: small, medium and the lock screen accessories.
    static let skillQueue = "SkillQueue"
    /// Up to `WidgetTimeline.pilotLimit` pilots in one medium widget.
    static let pilots = "SkillQueuePilots"

    static let all = [skillQueue, pilots]
}

/// Where the widget snapshot lives in the App Group container: one JSON file, and the pilots'
/// portraits as image files next to it. The app writes (`WidgetSnapshotWriter`), the widget only
/// reads.
nonisolated enum WidgetStore {
    private static let fileName = "WidgetSnapshot.json"
    private static let portraitsFolder = "Portraits"

    static var fileURL: URL? {
        AppGroup.containerURL?.appending(path: fileName)
    }

    static var portraitsURL: URL? {
        AppGroup.containerURL?.appending(path: portraitsFolder, directoryHint: .isDirectory)
    }

    /// The snapshot on disk; `nil` when there is none or it is of another version.
    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return WidgetSnapshot.decode(data)
    }

    /// The image file of `pilot`'s portrait, when the app has written one.
    static func portraitURL(of pilot: WidgetSnapshot.Pilot) -> URL? {
        guard let file = pilot.portraitFile else { return nil }
        return portraitsURL?.appending(path: file)
    }

    // MARK: - Writing (the app)

    /// Best-effort, like the ESI cache: a failed write leaves the previous file in place.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL, let data = snapshot.encoded() else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func portraitFileName(characterID: Int64) -> String {
        "\(characterID).jpg"
    }

    /// Whether the portrait of `characterID` is already on disk.
    static func hasPortrait(characterID: Int64) -> Bool {
        guard let url = portraitsURL?.appending(path: portraitFileName(characterID: characterID)) else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Writes the image data of a portrait; returns its file name, or `nil` when it failed.
    static func writePortrait(_ data: Data, characterID: Int64) -> String? {
        guard let folder = portraitsURL else { return nil }
        let name = portraitFileName(characterID: characterID)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appending(path: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// Deletes the portraits of everyone not in `characterIDs` — pilots signed out since.
    static func removePortraits(keeping characterIDs: Set<Int64>) {
        guard let folder = portraitsURL,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        let keep = Set(characterIDs.map(portraitFileName(characterID:)))
        for file in files where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
