import Foundation

/// The bundled demo data: anonymised ESI responses plus the tables the built-in handlers answer from.
public struct DemoArchive: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    /// The moment the responses were recorded; serving shifts their dates by `now - recordedAt`.
    public var recordedAt: Date
    /// The `X-Compatibility-Date` the responses were recorded with.
    public var compatibilityDate: String
    public var pilot: Pilot
    public var entries: [Entry]
    /// `/universe/names` answers, keyed by id.
    public var names: [String: Name]
    /// `/characters/{id}/assets/names` answers, keyed by item id.
    public var assetNames: [String: String]
    /// The local training plan the demo pilot starts with.
    public var plan: [PlanItem]

    public init(version: Int = DemoArchive.currentVersion, recordedAt: Date, compatibilityDate: String, pilot: Pilot,
                entries: [Entry] = [], names: [String: Name] = [:], assetNames: [String: String] = [:],
                plan: [PlanItem] = []) {
        self.version = version
        self.recordedAt = recordedAt
        self.compatibilityDate = compatibilityDate
        self.pilot = pilot
        self.entries = entries
        self.names = names
        self.assetNames = assetNames
        self.plan = plan
    }

    public struct Pilot: Codable, Sendable, Equatable {
        public var id: Int64
        public var name: String
        public var corporationID: Int64

        public init(id: Int64, name: String, corporationID: Int64) {
            self.id = id
            self.name = name
            self.corporationID = corporationID
        }
    }

    public struct Name: Codable, Sendable, Equatable {
        public var name: String
        /// A `/universe/names` category: `character`, `corporation`, `station`, …
        public var category: String

        public init(name: String, category: String) {
            self.name = name
            self.category = category
        }
    }

    public struct PlanItem: Codable, Sendable, Equatable {
        public var skillID: Int64
        public var level: Int

        public init(skillID: Int64, level: Int) {
            self.skillID = skillID
            self.level = level
        }
    }

    /// One recorded request and its response.
    public struct Entry: Codable, Sendable, Equatable {
        public var operationID: String
        public var method: String
        public var path: String
        /// Normalised query, see `DemoRequestKey.normalizedQuery(_:)`.
        public var query: String
        public var bodyDigest: String?
        public var status: Int
        public var headers: Headers
        /// The response body; `nil` when there was none.
        public var body: DemoJSON?
        /// The request body. Kept in recordings only; the exporter drops it.
        public var requestBody: DemoJSON?

        public init(operationID: String, method: String, path: String, query: String = "", bodyDigest: String? = nil,
                    status: Int = 200, headers: Headers = Headers(), body: DemoJSON?, requestBody: DemoJSON? = nil) {
            self.operationID = operationID
            self.method = method.uppercased()
            self.path = path
            self.query = query
            self.bodyDigest = bodyDigest
            self.status = status
            self.headers = headers
            self.body = body
            self.requestBody = requestBody
        }

        public var key: DemoRequestKey {
            DemoRequestKey(method: method, operationID: operationID, path: path, query: query, bodyDigest: bodyDigest)
        }

        /// The `page` query value, 1 when absent.
        public var page: Int {
            query.split(separator: "&")
                .first { $0.hasPrefix("page=") }
                .flatMap { Int($0.dropFirst(5)) } ?? 1
        }
    }

    public struct Headers: Codable, Sendable, Equatable {
        public var xPages: Int?
        public var lastModified: String?

        public init(xPages: Int? = nil, lastModified: String? = nil) {
            self.xPages = xPages
            self.lastModified = lastModified
        }
    }

    public static func decode(from data: Data) throws -> DemoArchive {
        try makeDecoder().decode(DemoArchive.self, from: data)
    }

    /// Pretty-printed, sorted keys: the bundled file is reviewed as a diff.
    public func encoded() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

/// What `DemoRecorder` writes: the raw responses of a real pilot, before anonymisation.
public struct DemoRecording: Codable, Sendable, Equatable {
    public var version: Int
    public var recordedAt: Date
    public var compatibilityDate: String
    /// The real pilot the responses belong to.
    public var pilotID: Int64
    /// The SSO owner hash of the real pilot, used only by the exporter's leak check.
    public var ownerHash: String?
    public var entries: [DemoArchive.Entry]

    public init(version: Int = DemoArchive.currentVersion, recordedAt: Date, compatibilityDate: String,
                pilotID: Int64, ownerHash: String? = nil, entries: [DemoArchive.Entry]) {
        self.version = version
        self.recordedAt = recordedAt
        self.compatibilityDate = compatibilityDate
        self.pilotID = pilotID
        self.ownerHash = ownerHash
        self.entries = entries
    }

    public static func decode(from data: Data) throws -> DemoRecording {
        try DemoArchive.makeDecoder().decode(DemoRecording.self, from: data)
    }

    public func encoded() throws -> Data {
        try DemoArchive.makeEncoder().encode(self)
    }
}
