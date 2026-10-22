import Foundation

/// URL builder for the EVE image server, which needs no authentication.
nonisolated enum EVEImage {
    private static let baseURL = URL(string: "https://images.evetech.net")!

    static func portrait(characterID: Int64, size: Int = 256) -> URL {
        baseURL
            .appending(path: "characters/\(characterID)/portrait")
            .appending(queryItems: [URLQueryItem(name: "size", value: "\(size)")])
    }

    static func logo(corporationID: Int64, size: Int = 64) -> URL {
        baseURL
            .appending(path: "corporations/\(corporationID)/logo")
            .appending(queryItems: [URLQueryItem(name: "size", value: "\(size)")])
    }

    static func logo(allianceID: Int64, size: Int = 64) -> URL {
        baseURL
            .appending(path: "alliances/\(allianceID)/logo")
            .appending(queryItems: [URLQueryItem(name: "size", value: "\(size)")])
    }

    /// The inventory icon of a type.
    ///
    /// The SDE references icons inside the game client's resources (`res:/ui/texture/...`), so
    /// icons are fetched from the image server by type id. Sizes must be powers of two; other
    /// values return `400`.
    static func icon(typeID: Int64, size: Int = 64) -> URL {
        baseURL
            .appending(path: "types/\(typeID)/icon")
            .appending(queryItems: [URLQueryItem(name: "size", value: "\(size)")])
    }

    /// The 3D render of a ship or structure. Types without a model return `404`, so the caller
    /// needs a fallback.
    static func render(typeID: Int64, size: Int = 512) -> URL {
        baseURL
            .appending(path: "types/\(typeID)/render")
            .appending(queryItems: [URLQueryItem(name: "size", value: "\(size)")])
    }
}
