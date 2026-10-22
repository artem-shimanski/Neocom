import DogmaKit

/// The fit's full stats, as shown on the stats screen and in the header summary.
///
/// Read once per snapshot; `sustainedTank` reuses the `capacitor` simulation result.
struct FitStatsSummary: Sendable {
    /// Damage by type.
    struct Damage: Sendable {
        /// All sources, fighters included.
        var dps: DamageVector
        /// Alpha strike: everything fired at once, cycle times ignored.
        var volley: DamageVector
        /// `dps` split by source; the five parts sum to `dps`.
        var turrets, launchers, drones, fighters, otherModules: DamageVector
    }

    /// Raw hit points by layer; see `effectiveHitPoints(against:)`.
    var hitPoints: HitPoints
    /// Resonances by layer (`1 - resistance`).
    ///
    /// Stored instead of effective figures so that a damage pattern change (`FitDamagePattern`)
    /// is applied without rebuilding the stats.
    var resonance: Resonance
    /// Resistance fractions (0…1) by layer.
    var resistances: Resistances
    /// Repair rates by layer, and the same rates capped by what the capacitor sustains.
    var tank: Tank
    var sustainedTank: Tank
    var damage: Damage
    var capacitor: CapacitorSimulator.Result
    var navigation: Navigation
    var targeting: Targeting
    /// Cargo hold, m³ (`AttributeID.capacity`).
    var cargoCapacity: Double
    /// Service module fuel; `nil` unless the hull is a structure.
    var fuel: FitFuel?
}

extension FitStatsSummary {
    /// Effective hit points by layer against `pattern`; only the weights' proportions matter.
    func effectiveHitPoints(against pattern: DamageVector) -> HitPoints {
        hitPoints.effective(resonance: resonance, damagePattern: pattern)
    }

    /// Repair rates as effective hit points per second against `pattern`.
    func effectiveTank(against pattern: DamageVector) -> Tank {
        tank.effective(resonance: resonance, damagePattern: pattern)
    }

    /// Sustained repair rates as effective hit points per second against `pattern`.
    func effectiveSustainedTank(against pattern: DamageVector) -> Tank {
        sustainedTank.effective(resonance: resonance, damagePattern: pattern)
    }

    /// Effective hit points against the uniform pattern, for comparing ships.
    var uniformEffectiveHitPoints: HitPoints {
        effectiveHitPoints(against: FitDamagePattern.uniform.vector)
    }
}
