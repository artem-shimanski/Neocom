import CryptoKit
import Foundation

/// The identity of an ESI request as the fixtures see it.
public struct DemoRequestKey: Hashable, Sendable, CustomStringConvertible {
    /// Upper-cased HTTP method.
    public let method: String
    public let operationID: String
    /// Path without the query string.
    public let path: String
    /// Normalised query, see `normalizedQuery(_:)`.
    public let query: String
    /// SHA-256 of the canonical request body; `nil` without a body.
    public let bodyDigest: String?

    public init(method: String, operationID: String, path: String, query: String, bodyDigest: String?) {
        self.method = method.uppercased()
        self.operationID = operationID
        self.path = path
        self.query = query
        self.bodyDigest = bodyDigest
    }

    /// - Parameter target: The request target, path and query, as in `HTTPRequest.path`.
    public init(method: String, operationID: String, target: String, body: Data?) {
        let (path, query) = Self.split(target: target)
        self.init(method: method, operationID: operationID, path: path,
                  query: Self.normalizedQuery(query), bodyDigest: Self.digest(of: body))
    }

    public var description: String {
        var text = "\(method) \(path)"
        if !query.isEmpty { text += "?\(query)" }
        text += " [\(operationID)]"
        if let bodyDigest { text += " body:\(bodyDigest.prefix(12))" }
        return text
    }

    /// Splits a request target into path and raw query.
    public static func split(target: String) -> (path: String, query: String?) {
        guard let index = target.firstIndex(of: "?") else { return (target, nil) }
        return (String(target[..<index]), String(target[target.index(after: index)...]))
    }

    /// Percent-decoded `name=value` pairs sorted, empty pairs and `page=1` dropped.
    public static func normalizedQuery(_ query: String?) -> String {
        guard let query, !query.isEmpty else { return "" }
        return query.split(separator: "&")
            .map { pair in
                let decoded = pair.replacingOccurrences(of: "+", with: " ")
                return decoded.removingPercentEncoding ?? decoded
            }
            .filter { !$0.isEmpty && $0 != "page=1" }
            .sorted()
            .joined(separator: "&")
    }

    /// SHA-256 hex of the body. A JSON body is canonicalised first: keys sorted, arrays of
    /// scalars sorted, so an id list sent in any order gives the same digest.
    public static func digest(of body: Data?) -> String? {
        guard let body, !body.isEmpty else { return nil }
        let canonical = (try? DemoJSON(data: body)).flatMap { try? canonicalize($0).data() } ?? body
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }

    public static func digest(of json: DemoJSON?) -> String? {
        guard let json, let data = try? json.data() else { return nil }
        return digest(of: data)
    }

    private static func canonicalize(_ json: DemoJSON) -> DemoJSON {
        switch json {
        case let .array(values):
            let values = values.map(canonicalize)
            guard values.allSatisfy(\.isScalar) else { return .array(values) }
            return .array(values.sorted { $0.sortKey < $1.sortKey })
        case let .object(object):
            return .object(object.mapValues(canonicalize))
        default:
            return json
        }
    }
}

private extension DemoJSON {
    var isScalar: Bool {
        switch self {
        case .array, .object: false
        default: true
        }
    }

    var sortKey: String {
        switch self {
        case .null: "0"
        case let .bool(value): "1\(value)"
        case let .int(value): "2" + String(format: "%020lld", value)
        case let .double(value): "3\(value)"
        case let .string(value): "4\(value)"
        case .array, .object: "5"
        }
    }
}
