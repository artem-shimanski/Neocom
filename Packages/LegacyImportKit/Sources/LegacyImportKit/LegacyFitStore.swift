import Foundation
import SQLite3

/// One fit read out of the old app's store.
public struct LegacyFit: Sendable {
    /// The old `ZUUID`; the new record keeps it, which is what makes the import idempotent.
    public var uuid: UUID
    public var name: String
    public var ship: LegacyShip
}

/// What the old store held: the fits that could be read, and a line for each one that could
/// not (no blob, no uuid, JSON that does not decode).
public struct LegacyFitStoreContents: Sendable {
    public var fits: [LegacyFit]
    public var failures: [String]
}

/// The old Neocom's Core Data store (`cloud.sqlite`), read with plain sqlite — no Core Data
/// model, no CloudKit. Only the fits are read.
public enum LegacyFitStore {
    public struct Failure: Error, CustomStringConvertible {
        public var description: String
    }

    /// Reads a copy of `url` (plus its `-wal` and `-shm`) made in a temporary directory, so
    /// the original is never opened and never changed. `nil` when there is no file at `url`.
    ///
    /// A copy opened read-write rather than the file opened `immutable`: an immutable open
    /// ignores the WAL, and the latest fits may still be sitting in it.
    public static func read(at url: URL) throws -> LegacyFitStoreContents? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let directory = fileManager.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let copy = directory.appendingPathComponent(url.lastPathComponent)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(at: source, to: URL(fileURLWithPath: copy.path + suffix))
        }
        return try readCopy(at: copy)
    }

    private static func readCopy(at url: URL) throws -> LegacyFitStoreContents {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw Failure(description: "Cannot open the old store: \(message(db))")
        }

        // Core Data creates every table up front, so a missing table means a different store.
        guard try !rows(db, "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'ZLOADOUT'", { _ in () }).isEmpty else {
            return LegacyFitStoreContents(fits: [], failures: [])
        }

        var fits: [LegacyFit] = []
        var failures: [String] = []
        let sql = """
            SELECT l.ZUUID, l.ZNAME, d.ZDATA
            FROM ZLOADOUT l LEFT JOIN ZLOADOUTDATA d ON d.Z_PK = l.ZDATA
            ORDER BY l.Z_PK
            """
        _ = try rows(db, sql) { statement in
            let uuidText = text(statement, 0)
            guard let uuid = uuidText.flatMap(UUID.init(uuidString:)) else {
                failures.append("A fit without a valid uuid: \(uuidText ?? "null").")
                return
            }
            guard let blob = sqlite3_column_blob(statement, 2) else {
                failures.append("Fit \(uuid): no data.")
                return
            }
            let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 2)))
            do {
                let ship = try JSONDecoder().decode(LegacyShip.self, from: data)
                let column = text(statement, 1) ?? ""
                let name = column.isEmpty ? (ship.name ?? "") : column
                fits.append(LegacyFit(uuid: uuid, name: name, ship: ship))
            } catch {
                failures.append("Fit \(uuid): \(error)")
            }
        }
        return LegacyFitStoreContents(fits: fits, failures: failures)
    }

    private static func rows<T>(_ db: OpaquePointer?, _ sql: String,
                                _ body: (OpaquePointer?) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure(description: "Cannot read the old store: \(message(db))")
        }
        var result: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: result.append(try body(statement))
            case SQLITE_DONE: return result
            default: throw Failure(description: "Cannot read the old store: \(message(db))")
            }
        }
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private static func message(_ db: OpaquePointer?) -> String {
        db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
    }
}
