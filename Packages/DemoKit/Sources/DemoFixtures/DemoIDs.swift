import Foundation

/// Ids that exist only in the demo: the demo pilot and everything the exporter makes up.
public enum DemoIDs {
    /// The demo pilot's character id.
    public static let characterID: Int64 = 8_000_000_000_000_001

    /// Ids of synthetic entities (characters, mails, killmails, mailing lists). Contains `characterID`.
    public static let syntheticRange: Range<Int64> = 8_000_000_000_000_000 ..< 8_000_000_001_000_000

    public static func contains(_ id: Int64) -> Bool {
        syntheticRange.contains(id)
    }

    /// Whether any numeric segment of a request path is a demo id.
    public static func contains(path: String) -> Bool {
        let path = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        return path.split(separator: "/").contains { segment in
            Int64(segment).map(contains) ?? false
        }
    }
}
