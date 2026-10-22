import Foundation

/// Moves recorded dates forward so that the demo always looks fresh.
///
/// Shifts every string in the ISO-8601 UTC form `yyyy-MM-ddTHH:mm:ss[.fff]Z` and
/// RFC 1123 HTTP dates. The shift is a whole number of seconds, so a fractional part is
/// carried over unchanged and the format stays as recorded.
public struct DemoRebaser: Sendable {
    /// Seconds added to every date.
    public let delta: Int64

    public init(delta: TimeInterval) {
        self.delta = Int64(delta.rounded(.down))
    }

    public init(recordedAt: Date, now: Date = .now) {
        self.init(delta: now.timeIntervalSince(recordedAt))
    }

    public func rebase(_ json: DemoJSON) -> DemoJSON {
        guard delta != 0 else { return json }
        switch json {
        case let .string(value):
            return rebase(timestamp: value).map(DemoJSON.string) ?? json
        case let .array(values):
            return .array(values.map(rebase))
        case let .object(object):
            return .object(object.mapValues(rebase))
        default:
            return json
        }
    }

    /// The shifted timestamp, or `nil` when `value` is not an ISO-8601 UTC timestamp.
    public func rebase(timestamp value: String) -> String? {
        guard let (seconds, fraction) = Self.parseTimestamp(value) else { return nil }
        return Self.formatTimestamp(seconds + delta) + fraction + "Z"
    }

    /// The shifted HTTP date, or `nil` when `value` is not an RFC 1123 date.
    public func rebase(httpDate value: String) -> String? {
        let formatter = Self.httpDateFormatter()
        guard let date = formatter.date(from: value) else { return nil }
        return formatter.string(from: date.addingTimeInterval(TimeInterval(delta)))
    }

    /// `date` in the ISO-8601 UTC form ESI uses, whole seconds.
    public static func timestamp(_ date: Date) -> String {
        formatTimestamp(Int64(date.timeIntervalSince1970.rounded(.down))) + "Z"
    }

    /// Seconds since 1970 and the fractional part including its dot (or empty).
    static func parseTimestamp(_ value: String) -> (Int64, String)? {
        let bytes = Array(value.utf8)
        guard bytes.count >= 20, bytes.last == UInt8(ascii: "Z") else { return nil }
        func digits(_ range: Range<Int>) -> Int64? {
            var result: Int64 = 0
            for index in range {
                let byte = bytes[index]
                guard byte >= 48, byte <= 57 else { return nil }
                result = result * 10 + Int64(byte - 48)
            }
            return result
        }
        let separators: [(Int, Character)] = [(4, "-"), (7, "-"), (10, "T"), (13, ":"), (16, ":")]
        guard separators.allSatisfy({ bytes[$0.0] == $0.1.asciiValue }) else { return nil }
        guard let year = digits(0 ..< 4), let month = digits(5 ..< 7), let day = digits(8 ..< 10),
              let hour = digits(11 ..< 13), let minute = digits(14 ..< 16), let second = digits(17 ..< 19),
              (1 ... 12).contains(month), (1 ... 31).contains(day), hour < 24, minute < 60, second < 61
        else { return nil }
        var fraction = ""
        if bytes.count > 20 {
            guard bytes[19] == UInt8(ascii: "."), bytes.count > 21, digits(20 ..< bytes.count - 1) != nil else { return nil }
            fraction = String(decoding: bytes[19 ..< bytes.count - 1], as: UTF8.self)
        } else if bytes[19] != UInt8(ascii: "Z") {
            return nil
        }
        let days = daysFromCivil(year: year, month: month, day: day)
        return (days * 86_400 + hour * 3600 + minute * 60 + second, fraction)
    }

    static func formatTimestamp(_ seconds: Int64) -> String {
        let days = seconds >= 0 ? seconds / 86_400 : (seconds - 86_399) / 86_400
        let rest = seconds - days * 86_400
        let (year, month, day) = civilFromDays(days)
        return String(format: "%04lld-%02lld-%02lldT%02lld:%02lld:%02lld",
                      year, month, day, rest / 3600, rest % 3600 / 60, rest % 60)
    }

    static func httpDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }

    // Proleptic Gregorian day arithmetic (H. Hinnant's algorithms).
    private static func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func civilFromDays(_ days: Int64) -> (Int64, Int64, Int64) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}
