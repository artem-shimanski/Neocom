import Foundation
import SDEKit

/// The units whose stored number is not what is shown: a resistance is stored as the multiplier
/// `0.85` and shown as `15%`, a required skill as its type id. Other units are plain suffixes.
enum SDEUnit: UInt16 {
    case milliseconds = 101
    case inverseAbsolutePercent = 108
    case modifierPercent = 109
    case inversedModifierPercent = 111
    case groupID = 115
    case typeID = 116
    case sizeClass = 117
    case attributeID = 119
    case absolutePercent = 127
    case boolean = 137
    case bonus = 139

    var id: UnitID { UnitID(rawValue: rawValue) }
}

/// What an attribute row points at when its value is an id rather than a quantity.
enum AttributeReferenceKind: Hashable {
    case type(TypeID)
    case group(GroupID)
    case attribute(AttributeID)
}

extension TypeAttributeRow {
    /// The localized name, falling back to the internal one for attributes without a `displayName`.
    var title: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return name
    }

    var unit: SDEUnit? {
        unitID.flatMap { SDEUnit(rawValue: $0.rawValue) }
    }

    /// The entity this row names, if its value is an id.
    ///
    /// The caller resolves the name: the value column is a `REAL`, so it cannot be joined.
    var reference: AttributeReferenceKind? {
        guard value > 0, let id = UInt32(exactly: value.rounded()) else { return nil }
        switch unit {
        case .typeID: return .type(TypeID(rawValue: id))
        case .groupID: return UInt16(exactly: id).map { .group(GroupID(rawValue: $0)) }
        case .attributeID: return UInt16(exactly: id).map { .attribute(AttributeID(rawValue: $0)) }
        default: return nil
        }
    }

    /// The value as it is shown when it is not a reference.
    var formattedValue: String { format(value) }

    /// The SDE's base figure, formatted the same way.
    var formattedBaseValue: String { format(baseValue) }

    /// Whether the fit changed the figure visibly. Compares the formatted strings, so floating-point
    /// noise such as `2.4000000000000004` does not count.
    var isChangedByFit: Bool { formattedValue != formattedBaseValue }

    /// Any other figure of this attribute, formatted the same way.
    func formatted(_ value: Double) -> String { format(value, digits: 1...4) }

    private func format(_ value: Double, digits: ClosedRange<Int> = 1...6) -> String {
        switch unit {
        case .boolean:
            return value == 0 ? String(localized: "No") : String(localized: "Yes")
        case .bonus:
            return "+" + Self.number(digits: digits, value)
        case .sizeClass:
            return Self.sizeClass(value)
        case .milliseconds:
            return withUnitName(Self.number(digits: digits, value / 1000))
        case .absolutePercent:
            return withUnitName(Self.number(digits: digits, value * 100))
        case .modifierPercent:
            return withUnitName(Self.number(digits: digits, (value - 1) * 100))
        case .inverseAbsolutePercent, .inversedModifierPercent:
            return withUnitName(Self.number(digits: digits, (1 - value) * 100))
        case .typeID, .groupID, .attributeID, .none:
            return withUnitName(Self.number(digits: digits, value))
        }
    }

    private func withUnitName(_ text: String) -> String {
        guard let unitName, !unitName.isEmpty else { return text }
        // Percent is attached to the number, other units follow after a space.
        return unitName == "%" ? text + unitName : text + " " + unitName
    }

    /// Rig and charge sizes are stored as a scale, not as a name.
    private static func sizeClass(_ value: Double) -> String {
        switch Int(value.rounded()) {
        case 1: String(localized: "Small")
        case 2: String(localized: "attribute.size.medium", defaultValue: "Medium", comment: "Rig or charge size, masculine like Small/Large")
        case 3: String(localized: "Large")
        case 4: String(localized: "X-Large")
        default: number(value)
        }
    }

    /// Grouped, with fraction digits only where needed.
    ///
    /// Values range from `0.0025` to `2.9e12`, so significant digits are used instead of a fixed
    /// number of fraction digits.
    private static func number(digits: ClosedRange<Int> = 1...6, _ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return value.formatted(.number.precision(.fractionLength(0)))
        }
        return value.formatted(.number.precision(.significantDigits(digits)))
    }
}
