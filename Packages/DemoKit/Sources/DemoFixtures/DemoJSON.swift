import Foundation

/// A JSON value kept as written: integers stay `Int64`, so ids survive a round trip exactly.
public enum DemoJSON: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([DemoJSON])
    case object([String: DemoJSON])

    /// Parses with `JSONSerialization`, which is much faster on large documents than
    /// `Decodable`, where every node would try each case in turn.
    public init(data: Data) throws {
        self = try DemoJSON(jsonObject: JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    /// Converts a `JSONSerialization` value.
    public init(jsonObject value: Any) throws {
        switch value {
        case is NSNull:
            self = .null
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.int64Value)
            }
        case let array as [Any]:
            self = .array(try array.map(DemoJSON.init(jsonObject:)))
        case let object as [String: Any]:
            self = .object(try object.mapValues(DemoJSON.init(jsonObject:)))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported JSON value \(type(of: value))"))
        }
    }

    /// Compact encoding with sorted keys.
    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public subscript(key: String) -> DemoJSON? {
        get {
            guard case let .object(object) = self else { return nil }
            return object[key]
        }
        set {
            guard case var .object(object) = self else { return }
            object[key] = newValue
            self = .object(object)
        }
    }

    public var bool: Bool? {
        if case let .bool(value) = self { value } else { nil }
    }

    public var double: Double? {
        switch self {
        case let .double(value): value
        case let .int(value): Double(value)
        default: nil
        }
    }

    public var int: Int64? {
        if case let .int(value) = self { value } else { nil }
    }

    public var string: String? {
        if case let .string(value) = self { value } else { nil }
    }

    public var array: [DemoJSON]? {
        if case let .array(value) = self { value } else { nil }
    }

    public var object: [String: DemoJSON]? {
        if case let .object(value) = self { value } else { nil }
    }
}

extension DemoJSON: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([DemoJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: DemoJSON].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}
