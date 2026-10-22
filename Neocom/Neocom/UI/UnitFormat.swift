import SwiftUI

/// ISK, formatted the one way the app formats it.
nonisolated enum ISK {
    static func string(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(2)))) ISK"
    }

    /// A market price: whole ISK from a thousand up (`9 200 000 ISK`), two decimals below it.
    static func price(_ value: Double) -> String {
        "\(priceFigure(value)) ISK"
    }

    /// `price` without the unit, for a place that sets the unit in a face of its own.
    static func priceFigure(_ value: Double) -> String {
        abs(value) >= 1000
            ? value.formatted(.number.precision(.fractionLength(0)))
            : value.formatted(.number.precision(.fractionLength(2)))
    }

    /// A price short enough for a narrow cell or an axis: `9.20M`, `1.25B`, `7.6K`, `0.42`.
    /// No unit — the cell's label says it is ISK.
    static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 1e12 {
            let figure = (value / 1e12).formatted(.number.precision(.fractionLength(2)))
            return String(localized: "\(figure)T", comment: "Compact ISK figure, trillions: a number followed by a one-letter suffix")
        }
        if magnitude >= 1e9 {
            let figure = (value / 1e9).formatted(.number.precision(.fractionLength(2)))
            return String(localized: "\(figure)B", comment: "Compact ISK figure, billions: a number followed by a one-letter suffix")
        }
        if magnitude >= 1e6 {
            let figure = (value / 1e6).formatted(.number.precision(.fractionLength(2)))
            return String(localized: "\(figure)M", comment: "Compact ISK figure, millions: a number followed by a one-letter suffix")
        }
        if magnitude >= 1e3 {
            let figure = (value / 1e3).formatted(.number.precision(.fractionLength(1)))
            return String(localized: "\(figure)K", comment: "Compact ISK figure, thousands: a number followed by a one-letter suffix")
        }
        return value.formatted(.number.precision(.fractionLength(2)))
    }
}

/// Skill points. Grouped, never abbreviated: "123 456 789 SP" is the number the game shows.
enum SkillPoints {
    static func string(_ value: Int64) -> String {
        String(localized: "\(value.formatted(.number)) SP", comment: "Skill points: a number and the abbreviation of skill points")
    }
}

/// Security status of a solar system or a character.
///
/// A system runs -1…1 and is written with one decimal, a character runs -10…10 with two; the colour
/// bands are shared.
enum SecurityStatus {
    /// `signed` is for a character's standing, which the game always writes with its sign:
    /// "+2.60". A system's security is written without one.
    static func string(_ value: Double, fractionLength: Int = 1, signed: Bool = false) -> String {
        value.formatted(.number
            .precision(.fractionLength(fractionLength))
            .sign(strategy: signed ? .always(includingZero: false) : .automatic))
    }

    /// Coloured from the raw value, not the rounded string: a 0.45 system prints as "0.5" and is
    /// still low security.
    static func color(_ value: Double) -> Color {
        if value >= 0.5 { return .hudOk }
        if value > 0 { return .hudWarn }
        return .hudDanger
    }
}

/// Times the way the game prints them: EVE time is UTC, dates are `2026.10.18 05:50`, and a span is
/// the two largest units with the second padded: `2d 07h`, `14h 00m`, `45m`.
nonisolated enum EVETime {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private static let dateTimeStyle = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits).\(month: .twoDigits).\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: .gmt, calendar: calendar)
    private static let monthDayStyle = Date.VerbatimFormatStyle(
        format: "\(month: .twoDigits).\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: .gmt, calendar: calendar)
    private static let timeStyle = Date.VerbatimFormatStyle(
        format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: .gmt, calendar: calendar)

    /// `2026.10.18 05:50`.
    static func dateTime(_ date: Date) -> String {
        date.formatted(dateTimeStyle)
    }

    private static let dateTimeSecondsStyle = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits).\(month: .twoDigits).\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
        timeZone: .gmt, calendar: calendar)

    /// `2026.10.18 05:50:51`, for moments the game records to the second (a killmail).
    static func dateTimeSeconds(_ date: Date) -> String {
        date.formatted(dateTimeSecondsStyle)
    }

    /// `10.18 05:50`, without the year.
    static func monthDayTime(_ date: Date) -> String {
        date.formatted(monthDayStyle)
    }

    private static let dateStyle = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits).\(month: .twoDigits).\(day: .twoDigits)",
        timeZone: .gmt, calendar: calendar)
    private static let monthDayOnlyStyle = Date.VerbatimFormatStyle(
        format: "\(month: .twoDigits).\(day: .twoDigits)",
        timeZone: .gmt, calendar: calendar)

    /// `2026.10.18` — a market day.
    static func date(_ date: Date) -> String {
        date.formatted(dateStyle)
    }

    /// `10.18`, a market day without the year.
    static func monthDay(_ date: Date) -> String {
        date.formatted(monthDayOnlyStyle)
    }

    /// `05:50`.
    static func time(_ date: Date) -> String {
        date.formatted(timeStyle)
    }

    /// `2d 07h`, `14h 00m`, `45m`. Rounded down to the minute, so a countdown never reads `0m`
    /// before it is due.
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(max(0, interval) / 60)
        let (days, hours, rest) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
        let (hh, mm) = (String(format: "%02d", hours), String(format: "%02d", rest))
        if days > 0 { return String(localized: "\(days)d \(hh)h", comment: "Game-style span: d = days, h = hours, m = minutes; the second figure is zero-padded") }
        if hours > 0 { return String(localized: "\(hours)h \(mm)m", comment: "Game-style span: d = days, h = hours, m = minutes; the second figure is zero-padded") }
        return String(localized: "\(rest)m", comment: "Game-style span: d = days, h = hours, m = minutes; the second figure is zero-padded")
    }

    /// `in 14h 00m`, `1d 03h ago`, or `now` within a minute either side.
    static func relative(_ date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        if abs(interval) < 60 { return String(localized: "now") }
        return interval > 0
            ? String(localized: "in \(duration(interval))")
            : String(localized: "\(duration(-interval)) ago")
    }
}
