import DogmaKit
import Foundation
import SDEKit

// Reads system effects from the SDE for the environment screen: sections and attribute wording.

/// A section of the environment screen.
enum EnvironmentCategory: Hashable, CaseIterable {
    case wormhole, incursion, triglavian, storm, other

    var title: String {
        switch self {
        case .wormhole: String(localized: "Wormhole")
        case .incursion: String(localized: "Incursion")
        case .triglavian: String(localized: "Triglavian Invasion")
        case .storm: String(localized: "Metaliminal Storms")
        case .other: String(localized: "Other")
        }
    }
}

/// One system effect, sorted into its section.
struct EnvironmentEffect: Identifiable, Hashable {
    let id: TypeID
    /// The full name in the database's language.
    let name: String
    let category: EnvironmentCategory
    /// 1…6 for a wormhole effect, `nil` for anything else.
    let wormholeClass: Int?
    /// `Pulsar` of `Class 4 Pulsar Effects` in the database's language when the name parses,
    /// the full name otherwise.
    let phenomenon: String

    /// `C4 Pulsar` for a wormhole effect, the full name otherwise.
    var shortName: String {
        guard let wormholeClass else { return name }
        return String(localized: "C\(wormholeClass) \(phenomenon)", comment: "Wormhole class and phenomenon, short: C4 Pulsar")
    }

    /// `Wormhole · Class 4`, or the section's name.
    var categoryLabel: String {
        guard let wormholeClass else { return category.title }
        return String(localized: "Wormhole · Class \(wormholeClass)")
    }
}

/// Every effect the screen offers, in sections.
///
/// Sections are derived from the English type name, whatever the database's language, since the
/// group has no market or meta group: `Class N <Phenomenon> Effects` for wormholes, `Incursion`
/// for incursions, a leading `Triglavian` for invasions, `Metaliminal` or `Storm` for storms.
/// Names matching no pattern go to `other`.
///
/// Internal types marked `(DO NOT TRANSLATE)` in their English names are excluded.
struct EnvironmentCatalog {
    private(set) var effects: [EnvironmentEffect] = []

    init(rows: [EnvironmentEffectRow]) {
        for row in rows {
            let english = row.englishName.isEmpty ? row.name : row.englishName
            guard english.range(of: "DO NOT TRANSLATE", options: .caseInsensitive) == nil else { continue }
            if let (wormholeClass, _) = Self.wormhole(english) {
                // Parsed from the localized name with the same pattern; the full name is the
                // fallback when a translation does not match.
                let phenomenon = Self.wormhole(row.name)?.phenomenon ?? row.name
                effects.append(EnvironmentEffect(id: row.id, name: row.name, category: .wormhole,
                                                 wormholeClass: wormholeClass, phenomenon: phenomenon))
            } else {
                effects.append(EnvironmentEffect(id: row.id, name: row.name, category: Self.category(english),
                                                 wormholeClass: nil, phenomenon: row.name))
            }
        }
    }

    /// The wormhole classes there are effects for, ascending.
    var wormholeClasses: [Int] {
        Set(effects.compactMap(\.wormholeClass)).sorted()
    }

    /// One class's phenomena, in query order (the language's alphabet).
    func wormholes(ofClass wormholeClass: Int) -> [EnvironmentEffect] {
        effects.filter { $0.wormholeClass == wormholeClass }
    }

    /// Every section except wormholes, in screen order, omitting empty ones.
    var sections: [EnvironmentSection] {
        EnvironmentCategory.allCases.filter { $0 != .wormhole }.compactMap { category in
            let effects = effects.filter { $0.category == category }
            return effects.isEmpty ? nil : EnvironmentSection(category: category, effects: effects)
        }
    }

    func effect(_ id: TypeID) -> EnvironmentEffect? {
        effects.first { $0.id == id }
    }

    private static func wormhole(_ name: String) -> (wormholeClass: Int, phenomenon: String)? {
        guard let match = name.wholeMatch(of: /Class ([1-6]) (.+) Effects/),
              let wormholeClass = Int(match.1) else { return nil }
        return (wormholeClass, String(match.2))
    }

    private static func category(_ english: String) -> EnvironmentCategory {
        if english.localizedCaseInsensitiveContains("Incursion") { return .incursion }
        if english.hasPrefix("Triglavian") { return .triglavian }
        if english.localizedCaseInsensitiveContains("Metaliminal")
            || english.localizedCaseInsensitiveContains("Storm") { return .storm }
        return .other
    }
}

/// One section of the screen below the wormholes.
struct EnvironmentSection: Identifiable {
    let category: EnvironmentCategory
    let effects: [EnvironmentEffect]

    var id: EnvironmentCategory { category }
}

// MARK: - Modifiers

/// One line of an effect's ACTIVE panel: what it changes and by how much.
struct EnvironmentModifierLine: Identifiable, Hashable {
    let id: AttributeID
    let title: String
    let value: String
}

extension EnvironmentModifierLine {
    /// The lines of one effect in attribute order; only the rows of `typeID` are read.
    ///
    /// A figure is worded by the operation of the effect modifier that applies it (`operations`),
    /// not by its unit, which is unreliable in this group:
    ///
    /// - A percentage (operation 6) on a damage resonance (attributes 109–113, 267–274) is shown
    ///   negated, as the resistance moves the opposite way: `36` becomes `−36%`. Four resonances
    ///   of one layer with the same figure fold into one line, `Armor resistances −36%`.
    /// - Any other percentage (operation 6): the signed figure, `−50%`.
    /// - A multiplication (operation 4) by a figure in `(0, 10]`: the signed change, `1.72` is `+72%`.
    /// - Anything else: the raw value with its unit.
    ///
    /// Attributes without a display name are internal flags and are omitted.
    static func lines(of typeID: TypeID,
                      attributes allAttributes: [EnvironmentAttributeRow],
                      operations allOperations: [EnvironmentOperationRow]) -> [EnvironmentModifierLine] {
        let attributes = allAttributes.filter { $0.typeID == typeID }
        let operations = allOperations.filter { $0.typeID == typeID }
        var operationByAttribute: [AttributeID: Int] = [:]
        // Attributes that are a percentage on a resonance, with their layer.
        var layerOfAttribute: [AttributeID: ResistanceLayer] = [:]
        for row in operations {
            guard let attributeID = row.attributeID, let operation = row.operation else { continue }
            if operationByAttribute[attributeID] == nil {
                operationByAttribute[attributeID] = operation
            }
            if operation == postPercent, let modified = row.modifiedAttributeID,
               let layer = ResistanceLayer(resonance: modified) {
                layerOfAttribute[attributeID] = layer
            }
        }

        // Layers whose four resonances all move by the same figure.
        var folded: [ResistanceLayer: Double] = [:]
        for layer in ResistanceLayer.allCases {
            let members = attributes.filter { layerOfAttribute[$0.id] == layer }
            let values = Set(members.map(\.value))
            if members.count == 4, values.count == 1, let value = values.first {
                folded[layer] = value
            }
        }

        var lines: [EnvironmentModifierLine] = []
        var emitted: Set<ResistanceLayer> = []
        for row in attributes {
            guard let displayName = row.displayName, !displayName.isEmpty else { continue }
            if let layer = layerOfAttribute[row.id], let value = folded[layer] {
                guard !emitted.contains(layer) else { continue }
                emitted.insert(layer)
                lines.append(EnvironmentModifierLine(id: row.id, title: layer.title, value: signedPercent(-value)))
                continue
            }
            let value: String
            if layerOfAttribute[row.id] != nil {
                value = signedPercent(-row.value)
            } else {
                switch operationByAttribute[row.id] {
                case postPercent:
                    value = signedPercent(row.value)
                case postMultiply where row.value > 0 && row.value <= 10:
                    value = signedPercent((row.value - 1) * 100)
                default:
                    value = raw(row)
                }
            }
            lines.append(EnvironmentModifierLine(id: row.id, title: displayName, value: value))
        }
        return lines
    }

    /// The dogma operations distinguished above.
    private static let postMultiply = 4
    private static let postPercent = 6

    /// `+72%`, `−36%`: a true minus sign, with a fraction only when significant.
    private static func signedPercent(_ value: Double) -> String {
        let magnitude = abs(value).formatted(.number.precision(.fractionLength(0...1)))
        if magnitude == 0.formatted(.number.precision(.fractionLength(0...1))) { return "0%" }
        return (value < 0 ? "\u{2212}" : "+") + magnitude + "%"
    }

    private static func raw(_ row: EnvironmentAttributeRow) -> String {
        let number = row.value.formatted(.number.precision(.significantDigits(1...6)))
        guard let unit = row.unitName, !unit.isEmpty else { return number }
        // Percent is attached to the number, other units follow after a space.
        return unit == "%" ? number + unit : number + " " + unit
    }
}

/// The three layers whose resistances an effect can fold into one line.
private enum ResistanceLayer: CaseIterable {
    case shield, armor, hull

    init?(resonance: AttributeID) {
        switch resonance {
        case .shieldEmDamageResonance, .shieldThermalDamageResonance,
             .shieldKineticDamageResonance, .shieldExplosiveDamageResonance:
            self = .shield
        case .armorEmDamageResonance, .armorThermalDamageResonance,
             .armorKineticDamageResonance, .armorExplosiveDamageResonance:
            self = .armor
        case .emDamageResonance, .thermalDamageResonance,
             .kineticDamageResonance, .explosiveDamageResonance:
            self = .hull
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .shield: String(localized: "Shield resistances")
        case .armor: String(localized: "Armor resistances")
        case .hull: String(localized: "Hull resistances")
        }
    }
}
