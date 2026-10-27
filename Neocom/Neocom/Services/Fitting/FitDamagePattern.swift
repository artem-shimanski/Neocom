import DogmaKit
import SwiftUI

/// The damage profile effective figures are computed against: a preset, an item's damage
/// split, or custom weights.
///
/// Not stored in the fit; it lives on the open editor (`FittingEditorModel.damagePattern`).
/// Weights are percentages; only their proportions matter.
nonisolated struct FitDamagePattern: Hashable, Sendable {
    /// Named patterns.
    nonisolated enum Preset: String, CaseIterable, Identifiable, Sendable {
        case uniform, em, thermal, kinetic, explosive
        case angelCartel, bloodRaiders, guristas, sanshasNation, serpentis, rogueDrones

        var id: String { rawValue }

        /// The uniform pattern and the four single-type ones, in the game's damage type order.
        static let damageTypes: [Preset] = [.uniform, .em, .thermal, .kinetic, .explosive]

        /// Display order: `damageTypes`, then the rest sorted by localized name.
        static var ordered: [Preset] {
            damageTypes + allCases.filter { !damageTypes.contains($0) }.sorted {
                String(localized: $0.title).localizedStandardCompare(String(localized: $1.title))
                    == .orderedAscending
            }
        }

        /// Whether the figures are an approximation (NPC factions).
        var isApproximate: Bool {
            !Self.damageTypes.contains(self)
        }

        var title: LocalizedStringResource {
            switch self {
            case .uniform: "Uniform"
            case .em: "EM"
            case .thermal: "Thermal"
            case .kinetic: "Kinetic"
            case .explosive: "Explosive"
            case .angelCartel: "Angel Cartel"
            case .bloodRaiders: "Blood Raiders"
            case .guristas: "Guristas"
            case .sanshasNation: "Sansha's Nation"
            case .serpentis: "Serpentis"
            case .rogueDrones: "Rogue Drones"
            }
        }

        /// Faction figures are the commonly used approximations, rounded to whole percent.
        var vector: DamageVector {
            switch self {
            case .uniform: DamageVector(em: 25, thermal: 25, kinetic: 25, explosive: 25)
            case .em: DamageVector(em: 100, thermal: 0, kinetic: 0, explosive: 0)
            case .thermal: DamageVector(em: 0, thermal: 100, kinetic: 0, explosive: 0)
            case .kinetic: DamageVector(em: 0, thermal: 0, kinetic: 100, explosive: 0)
            case .explosive: DamageVector(em: 0, thermal: 0, kinetic: 0, explosive: 100)
            case .angelCartel: DamageVector(em: 22, thermal: 7, kinetic: 26, explosive: 45)
            case .bloodRaiders: DamageVector(em: 55, thermal: 45, kinetic: 0, explosive: 0)
            case .guristas: DamageVector(em: 0, thermal: 14, kinetic: 86, explosive: 0)
            case .sanshasNation: DamageVector(em: 58, thermal: 42, kinetic: 0, explosive: 0)
            case .serpentis: DamageVector(em: 0, thermal: 53, kinetic: 47, explosive: 0)
            case .rogueDrones: DamageVector(em: 10, thermal: 17, kinetic: 29, explosive: 44)
            }
        }
    }

    /// An ammo charge or drone whose damage split defines the pattern.
    nonisolated struct Item: Hashable, Sendable {
        var typeID: TypeID
        var name: String
    }

    /// The preset, or `nil` for an item split or custom weights.
    private(set) var preset: Preset?
    /// The source item, or `nil`. Mutually exclusive with `preset`.
    private(set) var item: Item?
    /// The weights as set; may all be zero while editing. Arithmetic uses `vector`.
    private(set) var weights: DamageVector

    init(_ preset: Preset) {
        self.preset = preset
        self.weights = preset.vector
    }

    /// A pattern with custom weights; negative values are clamped to zero.
    static func custom(_ weights: DamageVector) -> FitDamagePattern {
        var pattern = FitDamagePattern(.uniform)
        pattern.preset = nil
        pattern.weights = DamageVector(em: max(weights.em, 0), thermal: max(weights.thermal, 0),
                                       kinetic: max(weights.kinetic, 0), explosive: max(weights.explosive, 0))
        return pattern
    }

    /// An item's damage split normalized to percent. `nil` for an item that deals no damage.
    static func item(_ item: Item, damage: DamageVector) -> FitDamagePattern? {
        let damage = DamageVector(em: max(damage.em, 0), thermal: max(damage.thermal, 0),
                                  kinetic: max(damage.kinetic, 0), explosive: max(damage.explosive, 0))
        let sum = damage.sum()
        guard sum > 0 else { return nil }
        var pattern = FitDamagePattern(.uniform)
        pattern.preset = nil
        pattern.item = item
        pattern.weights = damage * (100 / sum)
        return pattern
    }

    /// The engine's default pattern.
    static let uniform = FitDamagePattern(.uniform)

    /// The weights, or the uniform pattern when they sum to zero.
    var vector: DamageVector {
        weights.sum() > 0 ? weights : Preset.uniform.vector
    }

    /// The preset name, the item name, or `Custom`.
    var title: Text {
        if let preset { return Text(preset.title) }
        if let item { return Text(verbatim: item.name) }
        return Text(Self.customTitle)
    }

    /// Whether the figures are an approximation; true for NPC faction presets only.
    var isApproximate: Bool {
        preset?.isApproximate == true
    }

    /// A separate key from the catalog's `Custom`, which is plural in Russian.
    static let customTitle = LocalizedStringResource("damagePattern.custom", defaultValue: "Custom",
                                                     comment: "Name of a damage pattern the player set by hand")
}
