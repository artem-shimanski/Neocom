import Foundation

/// How the stats screen writes a fit's numbers.
///
/// One place, so the same quantity reads the same everywhere. Each function returns a finished
/// string with its unit. Numbers use `.number.precision(...)`, so grouping follows the locale;
/// percentages are whole.
enum FitStatFormat {
    /// Damage per second, e.g. "612.4 DPS". Keeps a tenth: a drone fit's DPS is only a few dozen.
    static func dps(_ value: Double) -> String {
        String(localized: "\(number(value, fraction: 0...1)) DPS", comment: "Damage per second, number then unit")
    }

    /// The number of a DPS alone, for places where the label names the unit.
    static func dpsFigure(_ value: Double) -> String {
        number(value, fraction: 0...1)
    }

    /// Hit points for the header strip as a figure and a unit: 14 100 is `("14.1", "K")`, 2 400 000
    /// is `("2.4", "M")`; below a thousand the number stands bare.
    ///
    /// The tank matrix prints the whole figure through `plain`, since HP or EHP is a column head
    /// there.
    static func hpCompact(_ value: Double) -> (figure: String, unit: String) {
        let rounded = value.rounded()
        if rounded >= 1_000_000 {
            return (number(value / 1_000_000, fraction: 0...2), String(localized: "M", comment: "Unit suffix: millions, after a compact hit-point figure"))
        }
        if rounded >= 1000 {
            return (number(value / 1000, fraction: 0...1), String(localized: "K", comment: "Unit suffix: thousands, after a compact hit-point figure"))
        }
        return (number(rounded, fraction: 0...0), "")
    }

    /// Repair rate, "84.5 HP/s".
    static func hpPerSecond(_ value: Double) -> String {
        String(localized: "\(number(value, fraction: 0...1)) HP/s", comment: "Unit: hit points per second, number then unit")
    }

    /// A time the way the game writes it: "7.3 s" up to a minute, "1 m 20 s" up to an hour, "1 h 2
    /// m" beyond. Longer times are rounded to whole seconds first, so 59.96 s is "1 m 0 s".
    static func seconds(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let tenths = (max(value, 0) * 10).rounded() / 10
        if tenths < 60 {
            return String(localized: "\(number(tenths, fraction: 0...1)) s", comment: "Unit: seconds, number then unit")
        }
        let whole = Int(tenths.rounded())
        if whole < 3600 {
            return String(localized: "\(whole / 60) m \(whole % 60) s", comment: "Duration: minutes and seconds")
        }
        return String(localized: "\(whole / 3600) h \(whole % 3600 / 60) m", comment: "Duration: hours and minutes")
    }

    /// A duration as a clock, "1:48" or "1:02:03", for cells too narrow for `seconds`. Whole
    /// seconds; an infinite duration is "—", a negative one "0:00".
    static func clock(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let whole = Int(max(value, 0).rounded())
        let (h, m, s) = (whole / 3600, whole % 3600 / 60, whole % 60)
        return h > 0
            ? "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
            : "\(m):\(String(format: "%02d", s))"
    }

    /// A fraction (0…1) as a whole percentage, "73%". Values outside the range are not clamped.
    static func percent(_ fraction: Double) -> String {
        "\(number(fraction * 100, fraction: 0...0))%"
    }

    /// Volume in cubic metres, "465 m³".
    static func m³(_ value: Double) -> String {
        String(localized: "\(number(value, fraction: 0...1)) m³", comment: "Unit: cubic metres, number then unit")
    }

    // MARK: - Units

    /// Energy, "2 400 GJ".
    static func energy(_ value: Double) -> String {
        String(localized: "\(number(value, fraction: 0...1)) GJ", comment: "Unit: gigajoules, number then unit")
    }

    /// What one module draws from the capacitor, "0.65 GJ/s". Unsigned, with two decimals.
    static func energyUse(_ value: Double) -> String {
        String(localized: "\(number(value, fraction: 0...2)) GJ/s", comment: "Unit: gigajoules per second, number then unit")
    }

    /// Energy per second, always signed: "+4.2 GJ/s", "-12.8 GJ/s".
    static func energyRate(_ value: Double) -> String {
        let text = value.formatted(.number.precision(.fractionLength(0...1))
            .sign(strategy: .always(includingZero: false)))
        return String(localized: "\(text) GJ/s", comment: "Unit: gigajoules per second, number then unit")
    }

    /// Speed, "412 m/s".
    static func speed(_ value: Double) -> String {
        String(localized: "\(number(value, fraction: 0...0)) m/s", comment: "Unit: metres per second, number then unit")
    }

    /// A distance in metres, in kilometres from 10 km on.
    static func distance(_ meters: Double) -> String {
        if abs(meters) >= 10_000 {
            return String(localized: "\(number(meters / 1000, fraction: 0...1)) km", comment: "Unit: kilometres, number then unit")
        }
        return String(localized: "\(number(meters, fraction: 0...0)) m", comment: "Unit: metres, number then unit")
    }

    /// Mass in kilograms, grouped and whole: "12 400 000 kg".
    static func mass(_ kilograms: Double) -> String {
        String(localized: "\(number(kilograms, fraction: 0...0)) kg", comment: "Unit: kilograms, number then unit")
    }

    /// Warp speed or range, "3.5 AU/s" / "7.2 AU".
    static func auPerSecond(_ value: Double) -> String {
        String(localized: "\(number(value, fraction: 0...2)) AU/s", comment: "Unit: astronomical units per second, number then unit")
    }

    static func au(_ value: Double) -> String {
        String(localized: "\(number(value, fraction: 0...1)) AU", comment: "Unit: astronomical units, number then unit")
    }

    /// Scan resolution, "483 mm".
    static func millimeters(_ value: Double) -> String {
        String(localized: "\(number(value, fraction: 0...0)) mm", comment: "Unit: millimetres, number then unit")
    }

    /// A bare number with the screen's usual decimals, for strengths and counts.
    static func plain(_ value: Double, fraction: ClosedRange<Int> = 0...1) -> String {
        number(value, fraction: fraction)
    }

    private static func number(_ value: Double, fraction: ClosedRange<Int>) -> String {
        value.formatted(.number.precision(.fractionLength(fraction)))
    }
}
