import Foundation
import SDEKit

// Wording for the implant and booster screens: the one-line bonus and a booster's side effects.

/// The one-line bonus of an item, from three sources in order:
///
/// 1. `dogmaImplantAttributes`, for implants and boosters raising the pilot's attributes:
///    `+4 Perception`; several attributes are joined with a comma.
/// 2. The single attribute the type's effects work through, with the type's value:
///    `+10% Duration Bonus`. Types whose effects reach several attributes get no line.
/// 3. Otherwise no entry.
///
/// The text keeps the case of the data.
enum ItemBonusLine {
    /// The game's attribute order, which is not alphabetical.
    private static let order: [CharacterAttribute] = [.perception, .memory, .willpower, .intelligence, .charisma]

    static func lines(attributeBonuses: [DogmaImplantAttribute],
                      modifiers: [ItemModifierRow]) -> [TypeID: String] {
        var lines: [TypeID: String] = [:]

        let byType = Dictionary(grouping: attributeBonuses, by: \.implantID)
        for (type, bonuses) in byType {
            let parts = order.compactMap { attribute -> String? in
                let total = bonuses.filter { $0.attribute == attribute }.reduce(0) { $0 + $1.bonus }
                guard total != 0 else { return nil }
                return "\(total > 0 ? "+" : "")\(total) \(name(of: attribute))"
            }
            if !parts.isEmpty { lines[type] = parts.joined(separator: ", ") }
        }

        // A type with several effects returns one row per effect; only the set of attributes matters.
        for (type, rows) in Dictionary(grouping: modifiers, by: \.typeID) where lines[type] == nil {
            let distinct = Dictionary(grouping: rows, by: \.id)
            guard distinct.count == 1, let row = rows.first, row.value != 0 else { continue }
            lines[type] = "\(row.signedValueText) \(row.title)"
        }
        return lines
    }

    private static func name(of attribute: CharacterAttribute) -> String {
        switch attribute {
        case .perception: String(localized: "Perception")
        case .memory: String(localized: "Memory")
        case .willpower: String(localized: "Willpower")
        case .intelligence: String(localized: "Intelligence")
        case .charisma: String(localized: "Charisma")
        }
    }
}

// MARK: - Figures

/// An attribute's value formatted as in the attribute list (`TypeAttributeRow`), signed:
/// `+10%`, `-20%`.
private func signed(_ text: String) -> String {
    guard let first = text.first, first.isNumber else { return text }
    return "+" + text
}

extension ItemModifierRow {
    /// `Duration Bonus`, or the internal name where the attribute has no display name.
    var title: String { attribute.title }

    /// `+10%`.
    var signedValueText: String { signed(attribute.formattedValue) }

    private var attribute: TypeAttributeRow {
        TypeAttributeRow(id: id, name: name, displayName: displayName, value: value, baseValue: value,
                         unitID: unitID, unitName: unitName, categoryID: nil, categoryName: nil)
    }
}

extension BoosterSideEffectRow {
    /// `Armor Hitpoint Penalty`.
    var title: String { attribute.title }

    /// `-20%`: the penalty as stored in the SDE, signed, before the pilot's skills modify it.
    var magnitudeText: String { magnitudeText(applied: nil) }

    /// The penalty at the strength the engine applies, e.g. `-15%` with `Nanite Control V`; `nil`
    /// gives the SDE figure.
    func magnitudeText(applied: Double?) -> String {
        signed(attribute(value: applied ?? value).formattedValue)
    }

    /// `20%`: the chance the effect fires.
    var chanceText: String {
        (chance * 100).formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    private var attribute: TypeAttributeRow { attribute(value: value) }

    private func attribute(value: Double) -> TypeAttributeRow {
        TypeAttributeRow(id: attributeID, name: name, displayName: displayName, value: value,
                         baseValue: self.value, unitID: unitID, unitName: unitName,
                         categoryID: nil, categoryName: nil)
    }
}
