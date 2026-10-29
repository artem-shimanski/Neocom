import DogmaKit
import Foundation

/// The fit as the editor draws it: one immutable value per engine state.
///
/// `FitStats` is `~Escapable`, so every value here is copied out inside `evaluate`. The
/// engine's own `Sendable` value types (`Resource`, `SlotCapacity`, the stats) are carried as
/// is. Each field costs an attribute read per entity per snapshot, so only drawn values are
/// included.
nonisolated struct FitSnapshot: Sendable {
    nonisolated struct Module: Sendable, Identifiable {
        var id: ModuleID
        var typeID: TypeID
        var slot: Entity.Module.Slot
        var socket: Int
        /// The requested state.
        var state: Entity.Module.State
        /// The state the engine applied; lower than `state` when the fit lacks resources.
        var effectiveState: Entity.Module.State
        /// The highest state the type supports: `.offline` for a rig, `.overloaded` for a turret.
        var maxAllowedState: Entity.Module.State
        var charge: TypeID?
        /// The number of charges in a full load: capacity over charge volume, rounded down.
        /// 0 without a charge.
        var chargeCount: Int = 0
        /// The charge groups and size the module accepts; empty when it takes no charge.
        var chargeGroups: [GroupID]
        var chargeSize: UInt8?
        /// Whether the module can be aimed at another ship (remote repairer, neutralizer, web).
        var isProjectable: Bool = false
        /// The fleet ship the module is aimed at. Session-only; documents do not store it.
        var target: PilotID?
        /// The applied mutaplasmid; `typeID` is then the resulting abyssal type.
        var mutation: Mutation?
    }

    /// A mutated module: the mutaplasmid, its base type and every roll the mutaplasmid has a
    /// range for.
    nonisolated struct Mutation: Sendable {
        var mutaplasmidTypeID: TypeID
        var baseTypeID: TypeID
        /// Rolls in attribute id order.
        var rolls: [MutationRoll]
    }

    nonisolated struct Drone: Sendable, Identifiable {
        var id: DroneID
        var typeID: TypeID
        var count: Int
        /// The maximum stack size; 5 for ordinary drones.
        var maxCount: Int
        var isActive: Bool
        /// Bay volume and bandwidth of a single drone; the caller multiplies by the count.
        var volume: Double
        var bandwidthUsed: Double
        /// Always `true` for a drone; carried for symmetry with `Module.isProjectable`.
        var isProjectable: Bool = true
        /// The fleet ship the stack is aimed at. Session-only.
        var target: PilotID?
        /// `.none` for an ordinary drone stack, otherwise the fighter squadron type.
        var squadron: Entity.Drone.Squadron = .none

        var isFighter: Bool { squadron != .none }
    }

    /// An effect another ship of the fleet aims at this one.
    ///
    /// Every aimed module or stack is listed; the amounts are set only where the engine
    /// computes one (a web or a disruptor has none).
    nonisolated struct Incoming: Sendable, Identifiable {
        nonisolated enum Source: Sendable, Hashable {
            case module(ModuleID)
            case drone(DroneID)
        }

        var id: Source
        /// The source ship.
        var pilotID: PilotID
        /// The target ship: the snapshot's own `pilotID` in `incoming`, any fleet ship in
        /// `FleetSnapshot.effects`.
        var targetID: PilotID
        var shipTypeID: TypeID
        /// The module or drone type.
        var typeID: TypeID
        /// Drones in the stack; 1 for a module.
        var count: Int
        /// Whether the source is running: a module at `.active` or above, a stack in space. An
        /// inactive source has no amounts.
        var isActive: Bool
        /// Remote repair received, HP/s by layer. Already included in this ship's `stats.tank`.
        var repair: FitStats.Module.Repair?
        /// Capacitor effect in GJ/s: positive for a transfer, negative for a neutralizer or
        /// nosferatu. Already included in this ship's `stats.capacitor`.
        var capacitor: Double?
    }

    /// The ship of this snapshot; commands not keyed by a module or drone id address it.
    var pilotID: PilotID

    /// An implant, keyed by its engine `slot`; the editor's commands address implants by slot.
    /// Type data (name, bonuses) is read from the SDE on screen.
    nonisolated struct Implant: Sendable, Identifiable {
        var id: ImplantID
        var typeID: TypeID
        /// `implantness`. Implants from external documents can lie outside slots 1…10.
        var slot: UInt16
    }

    /// A booster, keyed by `boosterness`.
    nonisolated struct Booster: Sendable, Identifiable {
        var id: BoosterID
        var typeID: TypeID
        var slot: UInt16
    }

    /// What the fit uses and the hull provides, as the engine computes it.
    nonisolated struct Resources: Sendable {
        var cpu: Resource
        var powerGrid: Resource
        var calibration: Resource
        /// Ordinary drones only; fighters use `fighterHangar`. Bandwidth counts drones in space.
        var droneBay: Resource
        var droneBandwidth: Resource
        /// Ordinary drones only; launched squadrons are `fighterTubes`.
        var dronesInSpace: SlotCapacity
        /// Total squadron volume against the hull's `fighterCapacity`.
        var fighterHangar = Resource(used: 0, total: 0)
        /// Launched squadrons against the hull's `fighterTubes`; docked squadrons take no tube.
        var fighterTubes = SlotCapacity(used: 0, total: 0)
        /// Squadrons of each type, launched or not, against that type's slots. Contains only
        /// the types the hull has slots or fighters for.
        var squadrons: [Entity.Drone.Squadron: SlotCapacity] = [:]
        var slots: [Entity.Module.Slot: SlotCapacity]
        var turrets: SlotCapacity
        var launchers: SlotCapacity
    }

    var shipTypeID: TypeID
    /// Every module, in rack and socket order.
    var modules: [Module]
    var drones: [Drone]
    /// Implants and boosters, each sorted by slot.
    var implants: [Implant] = []
    var boosters: [Booster] = []
    var resources: Resources
    /// The engine's stats. Always set once the fit has a hull.
    var stats: FitStatsSummary?
    /// Load warnings in player-readable form, carried on every snapshot for as long as the fit
    /// is open.
    var warnings: [String]
    /// Effects other fleet ships aim at this one, in fleet order. Empty for a fleet of one.
    var incoming: [Incoming] = []
    /// Environment effect type ids, in insertion order. Shared by the whole fleet.
    var environment: [TypeID] = []
}

/// The fleet around the selected ship: one line per ship, in fleet order.
///
/// Read in the same engine pass as the selected ship's `FitSnapshot`, since a command on one
/// ship can change the others' figures.
nonisolated struct FleetSnapshot: Sendable {
    nonisolated struct Ship: Sendable, Identifiable {
        /// The figures of the fleet overview: the full `FitStatsSummary` is read for the
        /// selected ship only.
        nonisolated struct Stats: Sendable {
            var dps: DamageVector
            var hitPoints: HitPoints
            var resonance: Resonance
            var capacitor: CapacitorSimulator.Result

            /// Effective hit points against the uniform pattern, for comparing ships.
            var uniformEffectiveHitPoints: HitPoints {
                hitPoints.effective(resonance: resonance, damagePattern: FitDamagePattern.uniform.vector)
            }
        }

        var id: PilotID
        var shipTypeID: TypeID
        var stats: Stats
    }

    var ships: [Ship]
    var selected: FitSnapshot
    /// Every module and stack of the fleet aimed at another fleet ship, in source fleet order.
    /// The selected ship's `incoming` is the subset aimed at it.
    var effects: [FitSnapshot.Incoming] = []
}

nonisolated extension FitSnapshot {
    /// Every type the fit references (hull, modules, charges, drones, implants, boosters), once
    /// each, sorted.
    ///
    /// The order is stable because the list is a `@LiteQuery` cache key.
    var typeIDs: [TypeID] {
        var ids = Set(modules.map(\.typeID))
        ids.formUnion(modules.compactMap(\.charge))
        ids.formUnion(drones.map(\.typeID))
        ids.formUnion(implants.map(\.typeID))
        ids.formUnion(boosters.map(\.typeID))
        ids.insert(shipTypeID)
        return ids.sorted { $0.rawValue < $1.rawValue }
    }

    /// Whether the stack's "in space" control may be turned on: a fighter squadron needs a free
    /// tube unless it is already launched. Mirrors `FitSession.setActive`.
    func canLaunch(_ drone: Drone) -> Bool {
        !drone.isFighter || drone.isActive || resources.fighterTubes.available > 0
    }
}

nonisolated extension FleetSnapshot.Ship.Stats {
    init(_ summary: FitStatsSummary) {
        self.init(dps: summary.damage.dps,
                  hitPoints: summary.hitPoints,
                  resonance: summary.resonance,
                  capacitor: summary.capacitor)
    }

    init(_ hull: borrowing FitStats.Hull) {
        self.init(dps: hull.dps(), hitPoints: hull.hitPoints, resonance: hull.resonance, capacitor: hull.capacitor())
    }
}
