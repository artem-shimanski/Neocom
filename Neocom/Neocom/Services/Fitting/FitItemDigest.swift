import DogmaKit

/// Engine figures for one fitted item, as listed on its item sheet.
///
/// `nil` means the engine provides no value, which is distinct from zero: the sheet draws a row
/// only for a present field. Read on demand by `FitSession.digest(of:)`, not part of
/// `FitSnapshot`.
///
/// `nonisolated` because the target defaults to `MainActor` isolation: the implicit `nil`
/// defaults would make the synthesized initializer main-actor isolated, while the digest is
/// built off the main actor.
nonisolated struct FitItemDigest: Sendable {
    // MARK: Fitting resources

    var cpu: Double?
    var powerGrid: Double?
    var calibration: Double?

    // MARK: Cycle

    /// Seconds, under the engine's reload policy (an ancillary repairer's reload is spread over
    /// the cycle).
    var cycleTime: Double?
    var reloadTime: Double?
    /// Capacitor drain in GJ/s.
    var capacitorUse: Double?

    // MARK: Effect

    /// Damage per second against `Target.zero`, as the fit total is summed.
    var dps: DamageVector?
    var volley: DamageVector?
    var optimal: Double?
    var falloff: Double?
    var accuracyScore: Double?
    var repair: FitStats.Module.Repair?
    /// Ore per second.
    var miningYield: Double?
    /// Fractional top-speed increase from a propulsion module (`0.5` is +50%), relative to the
    /// hull mass.
    var speedBonus: Double?

    // MARK: Drone stack

    /// Per drone, not per stack.
    var volumePerDrone: Double?
    var bandwidthPerDrone: Double?
    var maxVelocity: Double?

    // MARK: Subsystem

    /// Slots and hardpoints a T3 cruiser subsystem adds to its hull.
    var hiSlots: Double?
    var medSlots: Double?
    var lowSlots: Double?
    var turretHardpoints: Double?
    var launcherHardpoints: Double?
}
