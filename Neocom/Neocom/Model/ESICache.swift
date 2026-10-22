import Foundation

/// Disk cache of ESI data as plain JSON files, keyed by `kind` and `Owner`; never synced.
///
/// Schema-less: a file that fails to decode is treated as missing and the caller refetches.
/// Stateless file I/O, usable off the main actor.
nonisolated struct ESICache: Sendable {
    struct Entry<Value: Codable & Sendable>: Codable, Sendable {
        var value: Value
        var fetchedAt: Date
    }

    enum Owner: Sendable, Hashable {
        /// A character's data, removed by `removeAll(characterID:)`.
        case character(Int64)
        /// Public data shared by all characters.
        case universe
    }

    func load<Value: Codable & Sendable>(_ type: Value.Type, kind: String, characterID: Int64) -> Entry<Value>? {
        load(type, kind: kind, owner: .character(characterID))
    }

    func save<Value: Codable & Sendable>(_ entry: Entry<Value>, kind: String, characterID: Int64) {
        save(entry, kind: kind, owner: .character(characterID))
    }

    func load<Value: Codable & Sendable>(_ type: Value.Type, kind: String, owner: Owner) -> Entry<Value>? {
        let url = fileURL(kind: kind, owner: owner)
        guard let data = try? Data(contentsOf: url) else { return nil }
        // A corrupted or outdated file is `nil`, so the caller refetches.
        return try? Self.decoder.decode(Entry<Value>.self, from: data)
    }

    func save<Value: Codable & Sendable>(_ entry: Entry<Value>, kind: String, owner: Owner) {
        let url = fileURL(kind: kind, owner: owner)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Self.encoder.encode(entry)
            try data.write(to: url, options: .atomic)
        } catch {
            // Best effort: a failed write only means a refetch later.
        }
    }

    func removeAll(characterID: Int64) {
        try? FileManager.default.removeItem(at: directory(of: .character(characterID)))
    }

    /// Deletes the files of `owner` whose kind starts with `prefix` and that were last written
    /// before `date`. Bounds caches keyed by open-ended ids.
    func removeFiles(of owner: Owner, prefix: String, writtenBefore date: Date) {
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(at: directory(of: owner),
                                                          includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for url in urls where url.lastPathComponent.hasPrefix(prefix) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < date {
                try? manager.removeItem(at: url)
            }
        }
    }

    // MARK: - All owners

    /// Total bytes on disk and file count across all owners. Walks the directories; call off
    /// the main actor.
    static func diskUsage() -> (bytes: Int64, files: Int) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        var bytes: Int64 = 0
        var files = 0
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
            else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
                else { continue }
                files += 1
                bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return (bytes, files)
    }

    /// Deletes the cache directories of all owners, leaving the rest of Application Support (the
    /// SwiftData store) intact. Snapshots must be invalidated first so in-flight fetches do not
    /// write their files back.
    static func removeEverything() {
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - Paths

    private static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static var charactersRoot: URL {
        base.appendingPathComponent("Characters", isDirectory: true)
    }

    private static var universeRoot: URL {
        base.appendingPathComponent("Universe", isDirectory: true)
    }

    private static var roots: [URL] { [charactersRoot, universeRoot] }

    private func directory(of owner: Owner) -> URL {
        switch owner {
        case let .character(characterID):
            return Self.charactersRoot.appendingPathComponent(String(characterID), isDirectory: true)
        case .universe:
            return Self.universeRoot
        }
    }

    private func fileURL(kind: String, owner: Owner) -> URL {
        directory(of: owner).appendingPathComponent("\(kind).json")
    }

    // `.secondsSince1970` round-trips `Entry.fetchedAt` exactly; `.iso8601` truncates to
    // whole seconds.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
