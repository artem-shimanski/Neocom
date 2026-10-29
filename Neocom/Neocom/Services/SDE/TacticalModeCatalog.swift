import DogmaKit
import Foundation
import LiteRow
import SDEKit

// Tactical modes of a hull (Defense / Propulsion / Sharpshooter, Primary / Secondary / Tertiary)
// as the editor's switch shows them. The engine models a mode as a module in the `.mode` rack.

// MARK: - Rows

/// A mode type of one hull, named in the database's language and in English.
@Projection
struct TacticalModeRow: Sendable, Identifiable {
    var id: TypeID
    var name: String
    /// The language-independent name `TacticalMode` derives the role and icon from.
    var englishName: String
}

/// A mode type available to one hull; the first per hull is the default.
@Projection
struct TacticalModeHullRow: Sendable {
    var modeID: TypeID
    var hullID: TypeID
}

/// One attribute of a mode type with its dogma name; `mode…PostDiv` attributes have no display
/// name, so `TacticalModeBonus` labels them by it.
@Projection
struct TacticalModeAttributeRow: Sendable {
    var id: AttributeID
    var typeID: TypeID
    var name: String
    var displayName: String?
    var value: Double
}

extension FittingBrowser {
    /// The mode types of this hull in type id order, which is the switch order; the first is the
    /// default. The mode-to-hull link comes from `dogmaItemShipTypes`.
    static func tacticalModes(of hull: TypeID) -> SQLQuery<TacticalModeRow> {
        let kind = DogmaItemKind.mode
        let withHull = DogmaItem.all()
            .join(DogmaItemShipType.self) { item, link in item.id == link.itemID }
        let withType = withHull
            .join(TypeInfo.self) { item, _, type in item.id == type.id }
        let withName = withType
            .join(NameRow.self) { _, _, type, name in type.nameID == name.id }
        return withName
            .filter { item, link, _, _ in item.kind == kind && link.shipTypeID == hull }
            .select { item, _, _, name in
                TacticalModeRow.projection(id: item.id, name: name.text, englishName: name.textEn)
            }
            .order(by: { item, _, _, _ in item.id })
            .query()
    }

    /// The mode types of several hulls in type id order.
    static func tacticalModes(ofHulls hulls: [TypeID]) -> SQLQuery<TacticalModeHullRow> {
        let kind = DogmaItemKind.mode
        let withHull = DogmaItem.all()
            .join(DogmaItemShipType.self) { item, link in item.id == link.itemID }
        return withHull
            .filter { item, link in item.kind == kind && link.shipTypeID.in(hulls) }
            .select { item, link in TacticalModeHullRow.projection(modeID: item.id, hullID: link.shipTypeID) }
            .order(by: { item, _ in item.id })
            .query()
    }

    /// The attributes of these mode types that one of the type's own effects applies, in attribute
    /// id order. The SDE carries inert `mode…` attributes no effect reads; they are left out.
    static func tacticalModeAttributes(of modes: [TypeID]) -> SQLQuery<TacticalModeAttributeRow> {
        let withAttribute = TypeAttribute.all()
            .join(DogmaAttributeInfo.self) { row, attribute in row.attributeID == attribute.id }
        let withEffect = withAttribute
            .join(TypeEffect.self) { row, _, link in row.typeID == link.typeID }
        let withModifier = withEffect
            .join(DogmaEffectModifier.self) { _, attribute, link, modifier in
                link.effectID == modifier.effectID && modifier.modifyingAttributeID == attribute.id
            }
        let withName = withModifier
            .leftJoin(NameRow.self) { _, attribute, _, _, name in attribute.displayNameID == name.id }
        return withName
            .filter { row, _, _, _, _ in row.typeID.in(modes) }
            .select { row, attribute, _, _, name in
                TacticalModeAttributeRow.projection(id: attribute.id,
                                                    typeID: row.typeID,
                                                    name: attribute.name,
                                                    displayName: name.text,
                                                    value: row.value)
            }
            .order(by: { _, attribute, _, _, _ in attribute.id })
            .distinct()
            .query()
    }
}

// MARK: - Modes

/// One tactical mode of a hull: title, icon and the changes it makes.
struct TacticalMode: Identifiable, Hashable, Sendable {
    let id: TypeID
    /// The type's full name, e.g. `Hecate Defense Mode`.
    let name: String
    /// The name without hull and trailing "Mode": `Defense`, `Primary`.
    let title: String
    let systemImage: String
    /// In attribute order.
    let bonuses: [TacticalModeBonus]

    /// The largest change; the first in attribute order on a tie.
    var headline: TacticalModeBonus? {
        bonuses.reduce(nil) { best, bonus in
            guard let best else { return bonus }
            return bonus.magnitude > best.magnitude ? bonus : best
        }
    }

    /// The modes of one hull in the order of `rows`, each with its bonuses from `attributes`.
    /// `hullName` is the hull's name in the database's language, dropped from the title.
    static func modes(rows: [TacticalModeRow],
                      attributes: [TacticalModeAttributeRow],
                      hullName: String) -> [TacticalMode] {
        rows.enumerated().map { index, row in
            let role = role(ofEnglishName: row.englishName)
            return TacticalMode(id: row.id,
                                name: row.name,
                                title: title(of: row.name, hullName: hullName),
                                systemImage: systemImage(role: role, index: index),
                                bonuses: TacticalModeBonus.bonuses(of: attributes.filter { $0.typeID == row.id }))
        }
    }

    /// `Defense` from `Hecate Defense Mode`: the word before the trailing `Mode`.
    private static func role(ofEnglishName name: String) -> String {
        let words = name.split(separator: " ")
        guard words.count > 2, words.last == "Mode" else { return "" }
        return String(words[words.count - 2])
    }

    /// The localized name without the hull name and the word for "mode" where the language writes
    /// them separately (`Hecate Defense Mode`, `ヘカテ防衛モード`). Languages that fuse them
    /// (`Hecate-Verteidigungsmodus`) keep the name; an empty result keeps the name.
    private static func title(of name: String, hullName: String) -> String {
        var title = Substring(name)
        if !hullName.isEmpty, title.hasPrefix(hullName) {
            title = title.dropFirst(hullName.count)
            title = title.drop { $0 == " " || $0 == "-" || $0 == "\u{00A0}" }
        }
        for suffix in [" Mode", "モード", "模式", " 모드"] where title.hasSuffix(suffix) {
            title = title.dropLast(suffix.count)
            break
        }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }

    private static func systemImage(role: String, index: Int) -> String {
        switch role {
        case "Defense": "shield"
        case "Propulsion": "forward"
        case "Sharpshooter": "scope"
        // Primary / Secondary / Tertiary and further modes: numbered by position.
        default: index < 50 ? "\(index + 1).circle" : "circle"
        }
    }
}

/// What a mode changes, as the percentage a `PostDiv` makes: the attribute is divided by the
/// value `v`, a change of `1/v − 1` (`1.5` is −33.3%, `0.5` is +100%).
///
/// Labels prefer the SDE display name; the unnamed `mode…` attributes are labelled here, and
/// unknown ones are derived from the dogma name.
struct TacticalModeBonus: Identifiable, Hashable, Sendable {
    let id: AttributeID
    /// The card row label: `Targeting range`.
    let label: String
    /// The tile label: `Targeting`.
    let shortLabel: String
    /// The signed change as a fraction. Resistances are shown as resistances, so `+0.333` there
    /// is 33% less damage taken.
    let change: Double

    /// `+33.3%`, `−66.7%`, `+100%`.
    var value: String { Self.percent(change, fraction: 0...1) }
    /// `RESISTS +33%`.
    var headline: String { "\(shortLabel.uppercased()) \(Self.percent(change, fraction: 0...0))" }

    /// Rounded so that changes equal on paper tie despite floating-point noise.
    fileprivate var magnitude: Double { (abs(change) * 1e6).rounded() }

    /// One mode's bonuses in attribute order; four equal resistances fold into one line.
    static func bonuses(of attributes: [TacticalModeAttributeRow]) -> [TacticalModeBonus] {
        let modifiers = attributes.filter { $0.name.hasPrefix("mode") && $0.name.contains("PostDiv") && $0.value > 0 }
        let resistances = modifiers.filter { resistanceNames.contains($0.name) }
        let folds = resistances.count == resistanceNames.count && Set(resistances.map(\.value)).count == 1

        var bonuses: [TacticalModeBonus] = []
        for row in modifiers {
            let isResistance = resistanceNames.contains(row.name)
            if isResistance && folds {
                guard row.id == resistances.first?.id else { continue }
                bonuses.append(TacticalModeBonus(id: row.id,
                                                 label: String(localized: "Resistances"),
                                                 shortLabel: String(localized: "Resists"),
                                                 change: -(1 / row.value - 1)))
                continue
            }
            let (label, shortLabel) = labels(of: row)
            let change = 1 / row.value - 1
            bonuses.append(TacticalModeBonus(id: row.id, label: label, shortLabel: shortLabel,
                                             change: isResistance ? -change : change))
        }
        return bonuses
    }

    private static let resistanceNames: Set<String> = [
        "modeEmResistancePostDiv", "modeThermicResistancePostDiv",
        "modeKineticResistancePostDiv", "modeExplosiveResistancePostDiv",
    ]

    /// The row label and tile label, by dogma name.
    private static func labels(of row: TacticalModeAttributeRow) -> (String, String) {
        if let displayName = row.displayName, !displayName.isEmpty { return (displayName, displayName) }
        switch row.name {
        case "modeEmResistancePostDiv":
            return (String(localized: "EM resistance"), String(localized: "Resists"))
        case "modeThermicResistancePostDiv":
            return (String(localized: "Thermal resistance"), String(localized: "Resists"))
        case "modeKineticResistancePostDiv":
            return (String(localized: "Kinetic resistance"), String(localized: "Resists"))
        case "modeExplosiveResistancePostDiv":
            return (String(localized: "Explosive resistance"), String(localized: "Resists"))
        case "modeMaxRangePostDiv":
            return (String(localized: "Optimal & falloff"), String(localized: "Range"))
        case "modeMaxTargetRangePostDiv":
            return (String(localized: "Targeting range"), String(localized: "Targeting"))
        case "modeRadarStrengthPostDiv", "modeLadarStrengthPostDiv",
             "modeGravimetricStrengthPostDiv", "modeMagnetometricStrengthPostDiv":
            return (String(localized: "Sensor strength"), String(localized: "Sensors"))
        case "modeSignatureRadiusPostDiv":
            return (String(localized: "Signature radius"), String(localized: "Signature"))
        case "modeAgilityPostDiv":
            return (String(localized: "Inertia"), String(localized: "Inertia"))
        case "modeVelocityPostDiv":
            return (String(localized: "Max velocity"), String(localized: "Velocity"))
        case "modeMWDSigPenaltyPostDiv":
            return (String(localized: "MWD signature bloom"), String(localized: "MWD Bloom"))
        case "modeTrackingPostDiv":
            return (String(localized: "Tracking"), String(localized: "Tracking"))
        case "modeArmorRepDurationPostDiv":
            return (String(localized: "Armor repairer cycle"), String(localized: "Rep Cycle"))
        case "modeMWDVelocityPostDiv":
            return (String(localized: "MWD max velocity"), String(localized: "MWD Speed"))
        case "modeMWDCapPostDiv":
            return (String(localized: "MWD capacitor need"), String(localized: "MWD Cap"))
        case "modeDamageBonusPostDiv":
            return (String(localized: "Weapon damage"), String(localized: "Damage"))
        case "modeEwarResistancePostDiv":
            return (String(localized: "Damps & disruption on you"), String(localized: "EWAR"))
        case "modeRemoteRepairCapacitorCostPostDiv":
            return (String(localized: "Remote repair capacitor need"), String(localized: "RR Cap"))
        case "modeRemoteRepairBonusPostDiv":
            return (String(localized: "Remote repair amount"), String(localized: "Remote Rep"))
        case "modeShieldRechargePostDiv":
            return (String(localized: "Shield recharge time"), String(localized: "Recharge"))
        case "modeLightMissileMaxVelocityBonusPostDivSkua":
            return (String(localized: "Light missile velocity"), String(localized: "Missile Speed"))
        case "modeRocketMissileMaxVelocityBonusPostDivSkua":
            return (String(localized: "Rocket velocity"), String(localized: "Rocket Speed"))
        case "modeAnhingaMissileFlightTimePostDiv":
            return (String(localized: "Missile flight time"), String(localized: "Flight Time"))
        case "modeAnhingaMissileMaxVelocityPostDiv":
            return (String(localized: "Missile velocity"), String(localized: "Missile Speed"))
        case "modeAnhingaCruiseLauncherTorpedoLauncherRapidHeavyLauncherROFPostDiv":
            return (String(localized: "Launcher cycle time"), String(localized: "Cycle"))
        default:
            let label = derivedLabel(of: row.name)
            return (label, label)
        }
    }

    /// `modeShieldBoostPostDiv` → `Shield boost`: the words between the prefix and `PostDiv`.
    private static func derivedLabel(of name: String) -> String {
        var core = Substring(name.dropFirst("mode".count))
        if let range = core.range(of: "PostDiv") { core = core[..<range.lowerBound] }
        var words: [String] = []
        var word = ""
        for character in core {
            if character.isUppercase, !word.isEmpty, !(word.last?.isUppercase ?? false) {
                words.append(word)
                word = ""
            }
            word.append(character)
        }
        if !word.isEmpty { words.append(word) }
        guard let first = words.first else { return name }
        // Acronyms such as `MWD` keep their capitals; other words after the first are lowercased.
        let rest = words.dropFirst().map { $0.count > 1 && $0.allSatisfy(\.isUppercase) ? $0 : $0.lowercased() }
        return ([first] + rest).joined(separator: " ")
    }

    /// Signed, with a true minus and a fraction only when significant.
    private static func percent(_ change: Double, fraction: ClosedRange<Int>) -> String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(fraction))
        let magnitude = (abs(change) * 100).formatted(style)
        if magnitude == 0.0.formatted(style) { return "0%" }
        return (change < 0 ? "\u{2212}" : "+") + magnitude + "%"
    }
}
