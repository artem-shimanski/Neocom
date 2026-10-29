import DogmaKit
import Foundation

/// The single live engine session for one open fit or fleet.
///
/// A fleet is one engine with one pilot per ship, each loaded from its own document; a single
/// fit is a fleet of one. The session lives as long as the editor: reloading the document on
/// every edit would change the engine's entity ids under the interface.
///
/// Nothing from the engine leaves the actor: `FitStats` is `~Escapable`, so every read collects
/// its values inside the closure and returns a `FitSnapshot` / `FleetSnapshot`.
///
/// Commands mutate the engine and return nothing; the caller reads the result back with
/// `snapshot(selected:)`. Commands must be serialized by the caller: the actor admits the next
/// call at every suspension, so overlapping commands can observe each other's edits.
actor FitSession {
    private let engine: DogmaEngine
    /// The fleet's ships, in the order they were added. A single fit is one element.
    private(set) var ships: [PilotID]
    /// Warnings produced while loading each ship's document, attached to every snapshot.
    private var loadWarnings: [PilotID: [String]]
    /// The last successfully read state, returned when the engine cannot produce a fresh one.
    private var lastSnapshot: FleetSnapshot?

    private init(engine: DogmaEngine, ships: [PilotID], warnings: [PilotID: [String]], snapshot: FleetSnapshot) {
        self.engine = engine
        self.ships = ships
        self.loadWarnings = warnings
        self.lastSnapshot = snapshot
    }

    /// Loads one ship per document, in order, and returns the session with its first snapshot.
    ///
    /// Only the first pilot of each document is loaded, with every `target` dropped (targets
    /// index the document's own pilot list). The environment is taken from the first document
    /// only, since `Fit.load` appends rather than replaces it.
    ///
    /// Throws `FittingEngineError.noShip` for a document without a ship and
    /// `DogmaError.pilotLimitExceeded` when the fleet exceeds the engine's capacity.
    static func load(documents: [FitDocument]) async throws -> FitSession {
        guard !documents.isEmpty else { throw FittingEngineError.noShip }
        guard documents.count <= Fit.Pilots.maxCount else { throw DogmaError.pilotLimitExceeded }

        let engine = DogmaEngine()
        var ships: [PilotID] = []
        var warnings: [PilotID: [String]] = [:]
        for (index, document) in documents.enumerated() {
            let (pilot, shipWarnings) = try await addPilot(from: document, keepingEnvironment: index == 0, to: engine)
            ships.append(pilot)
            warnings[pilot] = shipWarnings
        }

        guard let snapshot = await read(from: engine, ships: ships, selected: ships[0], warnings: warnings) else {
            // The engine kept no pilot; the reason is already in the warnings.
            throw FittingEngineError.noShip
        }
        return FitSession(engine: engine, ships: ships, warnings: warnings, snapshot: snapshot)
    }

    /// Loads a single fit as a fleet of one.
    static func load(document: FitDocument) async throws -> FitSession {
        try await load(documents: [document])
    }

    /// The current state around `selected`, recalculated if the engine is dirty. `nil` only when
    /// the ship is not in the fleet and no earlier state of it exists.
    func snapshot(selected: PilotID) async -> FleetSnapshot? {
        if let fresh = await Self.read(from: engine, ships: ships, selected: selected, warnings: loadWarnings) {
            lastSnapshot = fresh
            return fresh
        }
        return lastSnapshot?.selected.pilotID == selected ? lastSnapshot : nil
    }

    /// The document for one ship, without targets or environment. The caller writes the
    /// environment back into each ship's record.
    func export(pilot: PilotID, name: String?) async -> FitDocument {
        await engine.export(pilot: pilot, name: name)
    }

    // MARK: - Fleet commands

    /// Adds a ship loaded from `document` as `load(documents:)` does, and returns its pilot.
    ///
    /// Throws `DogmaError.pilotLimitExceeded` when the fleet is full and
    /// `FittingEngineError.noShip` when the document has no ship.
    func addShip(document: FitDocument) async throws -> PilotID {
        guard ships.count < Fit.Pilots.maxCount else { throw DogmaError.pilotLimitExceeded }
        let (pilot, warnings) = try await Self.addPilot(from: document, keepingEnvironment: false, to: engine)
        ships.append(pilot)
        loadWarnings[pilot] = warnings
        return pilot
    }

    /// Removes the ship from the fleet together with every target other ships had on it.
    ///
    /// Targets are cleared explicitly: the next added ship can reuse the pilot index, and stale
    /// targets would silently land on it.
    func removeShip(_ pilot: PilotID) async {
        guard let index = ships.firstIndex(of: pilot) else { return }
        ships.remove(at: index)
        loadWarnings[pilot] = nil
        if lastSnapshot?.selected.pilotID == pilot { lastSnapshot = nil }

        await engine.edit { fit in
            let others = Array(fit.pilots.allIDs).filter { $0 != pilot }
            for other in others {
                let hull = fit[other.hull]
                var modules: [ModuleID] = []
                hull.modules.forEach { module in
                    if module.target == pilot.hull { modules.append(module.id) }
                }
                var drones: [DroneID] = []
                hull.drones.forEach { drone in
                    if drone.target == pilot.hull { drones.append(drone.id) }
                }
                for id in modules { fit[id].target = nil }
                for id in drones { fit[id].target = nil }
            }
            guard Self.exists(pilot, in: fit) else { return }
            fit[pilot].remove()
        }
    }

    /// Aims a module at another ship of the fleet, or clears its target.
    ///
    /// Silently ignored when the module is not projectable or the target is the module's own
    /// ship or not in the fleet.
    func setTarget(_ target: PilotID?, of id: ModuleID) async {
        let ships = ships
        await engine.edit { fit in
            guard Self.contains(id, in: fit) else { return }
            guard let target else {
                fit[id].target = nil
                return
            }
            guard target != id.hull.pilot, ships.contains(target), Self.exists(target, in: fit) else { return }
            guard fit[id].isProjectable else { return }
            fit[id].target = target.hull
        }
    }

    /// Aims a drone stack at another ship of the fleet, or clears its target.
    func setTarget(_ target: PilotID?, of id: DroneID) async {
        let ships = ships
        await engine.edit { fit in
            guard Self.contains(id, in: fit) else { return }
            guard let target else {
                fit[id].target = nil
                return
            }
            guard target != id.hull.pilot, ships.contains(target), Self.exists(target, in: fit) else { return }
            fit[id].target = target.hull
        }
    }

    /// Loads the document into the engine as one new pilot and returns it with its warnings.
    private static func addPilot(from document: FitDocument,
                                 keepingEnvironment: Bool,
                                 to engine: DogmaEngine) async throws -> (PilotID, [String]) {
        guard let first = document.pilots.first, first.ship != nil else { throw FittingEngineError.noShip }

        var trimmed = document
        trimmed.pilots = [untargeted(first)]
        if !keepingEnvironment { trimmed.environment = [] }
        let single = trimmed

        let added: PilotID?
        let importWarnings: [FitDocument.Warning]
        do {
            (added, importWarnings) = try await engine.edit { (fit) throws(FitDocument.Warning) -> (PilotID?, [FitDocument.Warning]) in
                let before = Set(fit.pilots.allIDs)
                let warnings = try fit.load(single, strict: false)
                let added = fit.pilots.allIDs.first { !before.contains($0) }
                if let added { Self.clampStates(of: added, in: fit) }
                return (added, warnings)
            }
        } catch {
            // In the lenient mode `load` throws only for a fleet that does not fit.
            if case let .pilotRejected(_, reason) = error, case .pilotLimitExceeded = reason {
                throw DogmaError.pilotLimitExceeded
            }
            throw error
        }
        guard let added else { throw FittingEngineError.noShip }
        return (added, importWarnings.map { String(localized: "Part of this fit could not be loaded: \(String(describing: $0)).") })
    }

    private static func untargeted(_ pilot: FitDocument.Pilot) -> FitDocument.Pilot {
        var pilot = pilot
        guard var ship = pilot.ship else { return pilot }
        for index in ship.modules.indices { ship.modules[index].target = nil }
        for index in ship.drones.indices { ship.drones[index].target = nil }
        pilot.ship = ship
        return pilot
    }

    /// Whether the pilot is still in the engine; the ship may have left the fleet since the
    /// command was queued.
    private static func exists(_ pilot: PilotID, in fit: borrowing Fit) -> Bool {
        fit.pilots.allIDs.contains(pilot)
    }

    // MARK: - Module commands

    /// Fits one more module of this type; the engine picks the rack and the first free socket.
    ///
    /// Throws the engine's `DogmaError` (`cantFit`, `rigSizeMismatch`, `subsystemSlotOccupied`,
    /// `groupLimitExceeded`, …). Exceeding slots, CPU or power grid is allowed and reported by
    /// the snapshot.
    func add(module typeID: TypeID, to pilot: PilotID) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.exists(pilot, in: fit) else { return }
            let hull = fit[pilot.hull]
            let modules = hull.modules
            _ = try modules.add(typeID)
        }
    }

    /// Removes the module together with its charge.
    func remove(module id: ModuleID) async {
        await engine.edit { fit in
            guard Self.contains(id, in: fit) else { return }
            fit[id].remove()
        }
    }

    /// Requests a state. The engine may apply a lower one when the fit cannot support it, hence
    /// `state` and `effectiveState` in the snapshot.
    func setState(_ state: Entity.Module.State, of id: ModuleID) async {
        await engine.edit { fit in
            guard Self.contains(id, in: fit) else { return }
            let module = fit[id]
            module.state = state
        }
    }

    func setCharge(_ typeID: TypeID, of id: ModuleID) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.contains(id, in: fit) else { return }
            let module = fit[id]
            try module.setCharge(typeID)
        }
    }

    /// Loads the charge into every module of the same type as `id`.
    ///
    /// Modules that reject the charge are skipped: modules of one type can still differ
    /// (a mutated one has its own capacity).
    func setCharge(_ typeID: TypeID, ofAllLike id: ModuleID) async {
        await engine.edit { fit in
            guard Self.contains(id, in: fit) else { return }
            let moduleTypeID = fit[id].typeID

            var ids: [ModuleID] = []
            let hull = fit[id.hull]
            hull.modules.forEach { module in
                if module.typeID == moduleTypeID { ids.append(module.id) }
            }

            for each in ids {
                try? fit[each].setCharge(typeID)
            }
        }
    }

    func removeCharge(of id: ModuleID) async {
        await engine.edit { fit in
            guard Self.contains(id, in: fit) else { return }
            let module = fit[id]
            module.charge?.remove()
        }
    }

    /// Replaces the module with another type, keeping socket, state and charge.
    ///
    /// The state is capped at the new type's `maxAllowedState`; the charge is kept only if the
    /// new type accepts it. When `add` throws, the old module is already removed and is not
    /// restored.
    func replace(_ id: ModuleID, with typeID: TypeID) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.contains(id, in: fit) else { return }
            let old = fit[id]
            let socket = old.socket
            let state = old.state
            let chargeTypeID = old.charge?.typeID
            fit[id].remove()

            let hull = fit[id.hull]
            let modules = hull.modules
            let newID = try modules.add(typeID).id

            let module = fit[newID]
            module.socket = socket
            module.state = min(state, module.maxAllowedState)
            if let chargeTypeID {
                try? module.setCharge(chargeTypeID)
            }
        }
    }

    // MARK: - Tactical mode

    /// Replaces the hull's tactical mode. Only the mode entity changes; other modules keep
    /// their ids.
    func setMode(_ typeID: TypeID, of pilot: PilotID) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.exists(pilot, in: fit) else { return }
            var current: [ModuleID] = []
            let hull = fit[pilot.hull]
            hull.modules.forEach(in: .mode) { current.append($0.id) }
            for id in current { fit[id].remove() }
            let modules = hull.modules
            _ = try modules.add(typeID)
        }
    }

    /// Fits the default mode from `defaults` into every hull whose mode rack is empty.
    ///
    /// The rack is read from the engine rather than the SDE: only a hull the engine gives a
    /// mode rack can fit a mode.
    func fitMissingModes(_ defaults: [TypeID: TypeID]) async {
        let ships = ships
        let empty = await engine.evaluate { stats -> [PilotID: TypeID] in
            let present = Array(stats.pilots.allIDs)
            var empty: [PilotID: TypeID] = [:]
            for pilot in ships where present.contains(pilot) {
                let hull = stats[pilot.hull]
                let capacity = hull.capacity(of: .mode)
                if capacity.total > 0, capacity.used == 0, let mode = defaults[hull.typeID] {
                    empty[pilot] = mode
                }
            }
            return empty
        }
        guard !empty.isEmpty else { return }
        await engine.edit { fit in
            for (pilot, mode) in empty where Self.exists(pilot, in: fit) {
                let hull = fit[pilot.hull]
                let modules = hull.modules
                _ = try? modules.add(mode)
            }
        }
    }

    /// Caps every module's state at what its type supports. The document import keeps stored
    /// states as is, and legacy fits carry active or overloaded states on passive modules.
    private static func clampStates(of pilot: PilotID, in fit: borrowing Fit) {
        var stale: [(ModuleID, Entity.Module.State)] = []
        let hull = fit[pilot.hull]
        hull.modules.forEach { module in
            if module.state > module.maxAllowedState { stale.append((module.id, module.maxAllowedState)) }
        }
        for (id, state) in stale { fit[id].state = state }
    }

    /// Whether the id still refers to a module of this fit.
    ///
    /// `Fit` subscripts trap on a dropped id, and commands come from a snapshot that may be one
    /// edit behind.
    private static func contains(_ id: ModuleID, in fit: borrowing Fit) -> Bool {
        let hull = fit[id.hull]
        return hull.modules.allIDs.contains { $0 == id }
    }

    // MARK: - Drone commands

    /// Adds one full stack of this drone type (`squadronSize`, 5 for an ordinary drone).
    ///
    /// The stack is put in space immediately. A fighter squadron is launched only while a
    /// fighter tube is free, otherwise it goes in docked. Throws the engine's `DogmaError`.
    func add(drone typeID: TypeID, to pilot: PilotID) async throws {
        let tubes = await fighterTubes(of: pilot)
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.exists(pilot, in: fit) else { return }
            let hull = fit[pilot.hull]
            let launched = Self.launchedSquadrons(in: hull.drones)
            let drone = try hull.drones.add(typeID)
            drone.isActive = drone.squadron == .none || launched < tubes
        }
    }

    /// Sets the stack size, clamped to `1...squadronSize`. Use `remove(drone:)` to remove the
    /// stack.
    func setCount(_ count: Int, of id: DroneID) async {
        await engine.edit { fit in
            guard Self.contains(id, in: fit) else { return }
            let drone = fit[id]
            let clamped = min(max(count, 1), Int(drone.squadronSize))
            drone.count = UInt8(clamped)
        }
    }

    /// Puts the stack in space or back in the bay. Only active stacks use bandwidth and deal
    /// damage.
    ///
    /// A fighter squadron is launched only into a free fighter tube; otherwise the command does
    /// nothing.
    func setActive(_ isActive: Bool, of id: DroneID) async {
        let tubes = isActive ? await fighterTubes(of: id.hull) : 0
        await engine.edit { fit in
            guard Self.contains(id, in: fit) else { return }
            let hull = fit[id.hull]
            let launched = Self.launchedSquadrons(in: hull.drones)
            let drone = fit[id]
            if isActive, drone.squadron != .none, !drone.isActive, launched >= tubes { return }
            drone.isActive = isActive
        }
    }

    /// The number of squadrons the hull may have in space at once; zero for a ship no longer in
    /// the fleet.
    private func fighterTubes(of pilot: PilotID) async -> Int {
        await fighterTubes(of: pilot.hull)
    }

    private func fighterTubes(of hull: HullID) async -> Int {
        await engine.evaluate({ stats -> Int in
            guard stats.pilots.allIDs.contains(where: { $0.hull == hull }) else { return 0 }
            return stats[hull].fighterTubes.total
        })
    }

    /// The number of fighter squadrons in space.
    private static func launchedSquadrons(in drones: borrowing Fit.Drones) -> Int {
        var count = 0
        drones.forEach { drone in
            if drone.squadron != .none, drone.isActive { count += 1 }
        }
        return count
    }

    /// Replaces the stack with another drone type, keeping whether it is in space and the count,
    /// capped at the new type's `squadronSize`.
    ///
    /// The new stack is appended at the end, since the engine lists stacks in insertion order.
    /// When `add` throws, the old stack is already removed and is not restored.
    func replace(_ id: DroneID, with typeID: TypeID) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.contains(id, in: fit) else { return }
            let old = fit[id]
            let count = old.count
            let isActive = old.isActive
            fit[id].remove()

            let hull = fit[id.hull]
            let drone = try hull.drones.add(typeID)
            drone.count = max(1, min(count, drone.squadronSize))
            drone.isActive = isActive
        }
    }

    /// Removes the stack together with its charge.
    func remove(drone id: DroneID) async {
        await engine.edit { fit in
            guard Self.contains(id, in: fit) else { return }
            fit[id].remove()
        }
    }

    /// Whether the id still refers to a drone stack of this fit; see `contains(_:in:)` for
    /// `ModuleID`.
    private static func contains(_ id: DroneID, in fit: borrowing Fit) -> Bool {
        let hull = fit[id.hull]
        return hull.drones.allIDs.contains { $0 == id }
    }

    // MARK: - Implant and booster commands

    /// Plugs an implant into the slot its type belongs to.
    ///
    /// Throws `implantSlotOccupied` for a taken slot, `attributeNotFound` for a category-20 type
    /// without an implant slot (a booster), and `typeNotFound`.
    func add(implant typeID: TypeID, to pilot: PilotID) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.exists(pilot, in: fit) else { return }
            let pilot = fit[pilot]
            let implants = pilot.implants
            try implants.add(typeID)
        }
    }

    /// Removes the implant from the slot. An empty slot is not an error.
    func remove(implantIn slot: UInt16, of pilot: PilotID) async {
        await engine.edit { fit in
            guard Self.exists(pilot, in: fit) else { return }
            let pilot = fit[pilot]
            let implants = pilot.implants
            implants[slot: slot]?.remove()
        }
    }

    /// Replaces the implant in `slot` in a single edit, since `add` into an occupied slot
    /// throws.
    ///
    /// `slot` is the old item's slot; the new type goes into the slot its `implantness` names.
    /// When `add` throws, the old implant is already removed and is not restored.
    func setImplant(_ typeID: TypeID, inSlot slot: UInt16, of pilot: PilotID) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.exists(pilot, in: fit) else { return }
            let pilot = fit[pilot]
            let implants = pilot.implants
            implants[slot: slot]?.remove()
            try implants.add(typeID)
        }
    }

    /// Plugs a booster into the slot its type belongs to. Throws as `add(implant:to:)`, with
    /// `boosterSlotOccupied` in place of `implantSlotOccupied`.
    func add(booster typeID: TypeID, to pilot: PilotID) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.exists(pilot, in: fit) else { return }
            let pilot = fit[pilot]
            let boosters = pilot.boosters
            try boosters.add(typeID)
        }
    }

    func remove(boosterIn slot: UInt16, of pilot: PilotID) async {
        await engine.edit { fit in
            guard Self.exists(pilot, in: fit) else { return }
            let pilot = fit[pilot]
            let boosters = pilot.boosters
            boosters[slot: slot]?.remove()
        }
    }

    /// Replaces the booster in `slot`. When `add` throws, the replaced booster is restored
    /// before the error is rethrown.
    func setBooster(_ typeID: TypeID, inSlot slot: UInt16, of pilot: PilotID) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.exists(pilot, in: fit) else { return }
            let pilot = fit[pilot]
            let boosters = pilot.boosters
            let replaced = boosters[slot: slot]?.typeID
            boosters[slot: slot]?.remove()
            do throws(DogmaError) {
                try boosters.add(typeID)
            } catch {
                if let replaced { _ = try? boosters.add(replaced) }
                throw error
            }
        }
    }

    /// Replaces the implant and booster lists in a single edit; `nil` leaves a list unchanged.
    ///
    /// Items that cannot be placed (slot taken by an earlier item, unknown type) are skipped.
    func setPilotItems(implants: [TypeID]?, boosters: [TypeID]?, of pilot: PilotID) async {
        await engine.edit { fit in
            guard Self.exists(pilot, in: fit) else { return }
            let pilot = fit[pilot]
            if let implants {
                let current = pilot.implants
                var ids: [ImplantID] = []
                current.forEach { ids.append($0.id) }
                for id in ids { current[id].remove() }
                for typeID in implants { _ = try? current.add(typeID) }
            }
            if let boosters {
                let current = pilot.boosters
                var ids: [BoosterID] = []
                current.forEach { ids.append($0.id) }
                for id in ids { current[id].remove() }
                for typeID in boosters { _ = try? current.add(typeID) }
            }
        }
    }

    // MARK: - Environment command

    /// Replaces the environment effects in a single edit; an empty list clears it. The
    /// environment applies to every ship of the fleet.
    ///
    /// Throws `typeNotFound`, or `invalidCategory` for a type outside the Celestial category.
    /// On failure the previous effects are restored.
    func setEnvironment(_ typeIDs: [TypeID]) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            let environment = fit.environment
            var previous: [TypeID] = []
            environment.forEach { previous.append($0.typeID) }
            environment.removeAll()
            do throws(DogmaError) {
                for typeID in typeIDs { _ = try environment.add(typeID) }
            } catch {
                environment.removeAll()
                for typeID in previous { _ = try? environment.add(typeID) }
                throw error
            }
        }
    }

    // MARK: - Mutation commands

    /// Applies a mutaplasmid; socket, state, target and charge are kept.
    ///
    /// On a module that is already mutated the mutaplasmid is swapped over the original base
    /// type, and each roll keeps its relative position within its range. A fresh mutation
    /// starts at the base values. The new ranges are known only after the swap, so the module
    /// is mutated twice in one edit.
    ///
    /// Throws `mutaplasmidNotFound`, `mutaplasmidNotApplicable`, `typeNotFound` or `cantFit`;
    /// the engine validates before changing the module, so a failure leaves it unchanged.
    func mutate(_ id: ModuleID, with mutaplasmidID: TypeID) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.contains(id, in: fit) else { return }
            let module = fit[id]
            var positions: [AttributeID: Double] = [:]
            if module.isMutated {
                module.forEachRoll { roll in
                    let range = roll.range
                    guard range.upperBound > range.lowerBound else { return }
                    positions[roll.attributeID] = (roll.value - range.lowerBound) / (range.upperBound - range.lowerBound)
                }
            }
            try module.mutate(with: mutaplasmidID)
            guard !positions.isEmpty else { return }
            var rolls: [(AttributeID, Double)] = []
            module.forEachRoll { roll in
                guard let position = positions[roll.attributeID] else { return }
                let range = roll.range
                rolls.append((roll.attributeID, range.lowerBound + position * (range.upperBound - range.lowerBound)))
            }
            try module.mutate(with: mutaplasmidID, rolls: rolls)
        }
    }

    /// Sets one roll to an absolute value; the engine clamps it to the mutaplasmid's range.
    /// Throws `attributeNotMutable` for an attribute without a range and `notMutated` for a
    /// module without a mutation.
    func setRoll(_ value: Double, for attributeID: AttributeID, of id: ModuleID) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.contains(id, in: fit) else { return }
            try fit[id].setRoll(value, for: attributeID)
        }
    }

    /// Resets every roll to the base value. A module that is not mutated is left unchanged.
    func resetRolls(of id: ModuleID) async {
        await engine.edit { fit in
            guard Self.contains(id, in: fit) else { return }
            let module = fit[id]
            guard module.isMutated else { return }
            module.resetRolls()
        }
    }

    /// Removes the mutation, restoring the base type and keeping the rest. A module that is not
    /// mutated is left unchanged.
    func demutate(_ id: ModuleID) async throws {
        try await engine.edit { (fit) throws(DogmaError) in
            guard Self.contains(id, in: fit) else { return }
            let module = fit[id]
            guard module.isMutated else { return }
            try module.demutate()
        }
    }

    // MARK: - Skill command

    /// Replaces the whole skill set, in the document's shape: `default` and `levels` are only
    /// meaningful together.
    func setSkills(_ skills: FitDocument.Skills, of pilot: PilotID) async {
        await engine.edit { fit in
            guard Self.exists(pilot, in: fit) else { return }
            let pilot = fit[pilot]
            let pilotSkills = pilot.skills
            pilotSkills.setAll(to: skills.default)
            // The last entry wins on a duplicate skill: the document is external JSON.
            let levels = Dictionary(skills.levels.map { ($0.type, $0.level) },
                                    uniquingKeysWith: { _, last in last })
            pilotSkills.setLevels(levels)
        }
    }

    // MARK: - One entity's attributes

    /// The engine's values of `ids` for the module.
    ///
    /// Reads through `evaluate` only; `edit` would mark the session dirty and force a
    /// recalculation on the next snapshot. A missing entity returns an empty dictionary.
    ///
    /// Ids without an engine value are omitted rather than read with `default: .sde`, which
    /// returns the attribute's global default instead of the type's own value.
    func attributes(of id: ModuleID, ids: [AttributeID]) async -> [AttributeID: Double] {
        await engine.evaluate({ stats -> [AttributeID: Double] in
            guard Self.contains(id, in: stats) else { return [:] }
            let module = stats[id]
            return Self.values(of: module.attributes, ids: ids)
        })
    }

    /// The engine's values of `ids` for the charge in the module; empty when there is none.
    func attributes(ofChargeIn id: ModuleID, ids: [AttributeID]) async -> [AttributeID: Double] {
        await engine.evaluate({ stats -> [AttributeID: Double] in
            guard Self.contains(id, in: stats) else { return [:] }
            let module = stats[id]
            guard let charge = module.charge else { return [:] }
            return Self.values(of: charge.attributes, ids: ids)
        })
    }

    /// The engine's values of `ids` for every fitted booster, modifiers applied (penalties are
    /// reduced by Nanite Control, attribute 1126).
    ///
    /// Every fitted booster has a key, with an empty dictionary when none of `ids` has a value.
    func attributesOfBoosters(of pilot: PilotID, ids: [AttributeID]) async -> [BoosterID: [AttributeID: Double]] {
        await engine.evaluate({ stats -> [BoosterID: [AttributeID: Double]] in
            guard stats.pilots.allIDs.contains(pilot) else { return [:] }
            let pilot = stats[pilot]
            var boosters: [BoosterID: [AttributeID: Double]] = [:]
            pilot.boosters.forEach { booster in
                boosters[booster.id] = Self.values(of: booster.attributes, ids: ids)
            }
            return boosters
        })
    }

    /// The engine's values of `ids` for one implant; empty when it or the pilot is gone.
    func attributes(of id: ImplantID, of pilot: PilotID, ids: [AttributeID]) async -> [AttributeID: Double] {
        await engine.evaluate({ stats -> [AttributeID: Double] in
            guard stats.pilots.allIDs.contains(pilot) else { return [:] }
            let pilot = stats[pilot]
            guard pilot.implants.allIDs.contains(id) else { return [:] }
            let implant = stats[id]
            return Self.values(of: implant.attributes, ids: ids)
        })
    }

    /// The engine's values of `ids` for one booster; empty when it or the pilot is gone.
    func attributes(of id: BoosterID, of pilot: PilotID, ids: [AttributeID]) async -> [AttributeID: Double] {
        await engine.evaluate({ stats -> [AttributeID: Double] in
            guard stats.pilots.allIDs.contains(pilot) else { return [:] }
            let pilot = stats[pilot]
            guard pilot.boosters.allIDs.contains(id) else { return [:] }
            let booster = stats[id]
            return Self.values(of: booster.attributes, ids: ids)
        })
    }

    /// The engine's values of `ids` for a drone stack.
    func attributes(of id: DroneID, ids: [AttributeID]) async -> [AttributeID: Double] {
        await engine.evaluate({ stats -> [AttributeID: Double] in
            guard Self.contains(id, in: stats) else { return [:] }
            let drone = stats[id]
            return Self.values(of: drone.attributes, ids: ids)
        })
    }

    /// The engine's values of `ids` for a ship's hull; empty for a ship no longer in the fleet.
    func attributes(ofHullOf pilot: PilotID, ids: [AttributeID]) async -> [AttributeID: Double] {
        await engine.evaluate({ stats -> [AttributeID: Double] in
            guard stats.pilots.allIDs.contains(pilot) else { return [:] }
            let hull = stats[pilot.hull]
            return Self.values(of: hull.attributes, ids: ids)
        })
    }

    /// `FitStats` counterparts of the `Fit` checks above.
    private static func contains(_ id: ModuleID, in stats: borrowing FitStats) -> Bool {
        let hull = stats[id.hull]
        return hull.modules.allIDs.contains { $0 == id }
    }

    private static func contains(_ id: DroneID, in stats: borrowing FitStats) -> Bool {
        let hull = stats[id.hull]
        return hull.drones.allIDs.contains { $0 == id }
    }

    private static func values(of attributes: borrowing EntityAttributes, ids: [AttributeID]) -> [AttributeID: Double] {
        var values: [AttributeID: Double] = [:]
        for id in ids {
            if let value = attributes[id] { values[id] = value }
        }
        return values
    }

    // MARK: - One entity's digest

    /// The figures the item sheet lists for one module, read on demand rather than carried on
    /// every snapshot.
    ///
    /// Reads through `evaluate` only and checks the id first, as `attributes(of:ids:)` does. A
    /// missing module returns an empty digest.
    func digest(of id: ModuleID) async -> FitItemDigest {
        await engine.evaluate({ stats -> FitItemDigest in
            guard Self.contains(id, in: stats) else { return FitItemDigest() }
            let module = stats[id]
            var digest = FitItemDigest()

            digest.cpu = Self.positive(module.cpuUse)
            digest.powerGrid = Self.positive(module.powerGridUse)
            digest.calibration = Self.positive(module.calibrationUse)

            digest.cycleTime = Self.positive(module.cycleTime())
            digest.reloadTime = Self.positive(module.reloadTime)
            digest.capacitorUse = Self.positive(module.capUse())

            // Zero for anything not currently firing; zero means no damage row.
            digest.dps = Self.nonZero(module.dps(to: .zero))
            digest.volley = Self.nonZero(module.volleyDamage)
            digest.optimal = Self.positive(module.optimal)
            digest.falloff = Self.positive(module.falloff)
            digest.accuracyScore = Self.positive(module.accuracyScore)
            digest.repair = module.repair()
            digest.miningYield = Self.positive(module.miningYield())

            if let propulsion = module.propulsion {
                // The speed bonus is `thrust` over the hull mass including this module's
                // `massAddition`. An active module is already in the hull's mass; an inactive one
                // is not.
                let mass = stats[id.hull].navigation.mass
                    + (module.effectiveState >= .active ? 0 : propulsion.massAddition)
                digest.speedBonus = mass > 0 ? Self.positive(propulsion.thrust / mass) : nil
            }

            let slots = module.slotModifiers
            let hardpoints = module.hardpointModifiers
            digest.hiSlots = Self.positive(slots[.hi])
            digest.medSlots = Self.positive(slots[.med])
            digest.lowSlots = Self.positive(slots[.low])
            digest.turretHardpoints = Self.positive(hardpoints[.turret])
            digest.launcherHardpoints = Self.positive(hardpoints[.launcher])

            return digest
        })
    }

    /// The figures the item sheet lists for one drone stack.
    ///
    /// Damage is for the whole stack; volume and bandwidth are per drone. Range and tracking are
    /// read for ordinary drones only: a fighter has them per ability.
    func digest(of id: DroneID) async -> FitItemDigest {
        await engine.evaluate({ stats -> FitItemDigest in
            guard Self.contains(id, in: stats) else { return FitItemDigest() }
            let drone = stats[id]
            var digest = FitItemDigest()

            digest.cycleTime = Self.positive(drone.cycleTime())
            digest.dps = Self.nonZero(drone.dps())
            digest.volley = Self.nonZero(drone.volleyDamage)
            if drone.squadron == .none {
                digest.optimal = Self.positive(drone.optimal(of: .drone))
                digest.falloff = Self.positive(drone.falloff(of: .drone))
                digest.accuracyScore = Self.positive(drone.accuracyScore(of: .drone))
            }
            digest.miningYield = Self.positive(drone.miningYield())

            digest.volumePerDrone = Self.positive(drone.volume)
            digest.bandwidthPerDrone = Self.positive(drone.bandwidthUsed)
            digest.maxVelocity = Self.positive(drone.maxVelocity)

            return digest
        })
    }

    /// The value, or `nil` when it is zero or not finite: a digest row is shown only for a
    /// nonzero figure.
    private static func positive(_ value: Double) -> Double? {
        value > 0 && value.isFinite ? value : nil
    }

    private static func positive(_ value: Int?) -> Double? {
        value.flatMap { positive(Double($0)) }
    }

    private static func nonZero(_ vector: DamageVector) -> DamageVector? {
        vector.sum() > 0 ? vector : nil
    }

    // MARK: - Reading the engine

    /// Collects the selected ship's snapshot and the fleet's lines. `nil` when the selected
    /// ship is not in the engine.
    ///
    /// Only the selected ship is snapshotted in full; the other ships give their overview
    /// figures and the effects they aim at another ship. Static so that `load` can call it
    /// before the session exists.
    private static func read(from engine: DogmaEngine,
                             ships: [PilotID],
                             selected: PilotID,
                             warnings: [PilotID: [String]]) async -> FleetSnapshot? {
        await engine.evaluate({ stats -> FleetSnapshot? in
            let present = Array(stats.pilots.allIDs)
            guard present.contains(selected) else { return nil }
            let isFleet = ships.count > 1
            let pilot = stats[selected].snapshot()
            let hull = pilot.hull

            var modules: [FitSnapshot.Module] = []
            // Sorted by rack and socket: entity ids are not allocated in socket order.
            for slot in Entity.Module.Slot.allCases {
                let inRack = hull.modules.filter { $0.slot == slot }.sorted { $0.socket < $1.socket }
                modules.append(contentsOf: inRack.map { module in
                    var mutation: FitSnapshot.Mutation?
                    if module.isMutated, let mutaplasmid = module.mutaplasmidTypeID, let base = module.baseTypeID {
                        mutation = FitSnapshot.Mutation(mutaplasmidTypeID: mutaplasmid, baseTypeID: base, rolls: module.rolls)
                    }
                    return FitSnapshot.Module(id: module.id,
                                              typeID: module.typeID,
                                              slot: slot,
                                              socket: module.socket,
                                              state: module.state,
                                              effectiveState: module.effectiveState,
                                              maxAllowedState: module.maxAllowedState,
                                              charge: module.charge?.typeID,
                                              chargeCount: module.chargeCount,
                                              chargeGroups: module.chargeGroup ?? [],
                                              chargeSize: module.chargeSize?.rawValue,
                                              isProjectable: module.isProjectable,
                                              target: isFleet ? module.target?.pilot : nil,
                                              mutation: mutation)
                })
            }

            let drones = hull.drones.map { drone in
                FitSnapshot.Drone(id: drone.id,
                                  typeID: drone.typeID,
                                  count: drone.count,
                                  maxCount: drone.squadronSize,
                                  isActive: drone.isActive,
                                  volume: drone.volume,
                                  bandwidthUsed: drone.bandwidthUsed,
                                  isProjectable: drone.isProjectable,
                                  target: isFleet ? drone.target.map { PilotID(rawValue: $0.pilot) } : nil,
                                  squadron: drone.squadron)
            }

            let resources = FitSnapshot.Resources(
                cpu: hull.cpu,
                powerGrid: hull.powerGrid,
                calibration: hull.calibration,
                droneBay: hull.droneBay,
                droneBandwidth: hull.droneBandwidth,
                dronesInSpace: hull.dronesInSpace,
                fighterHangar: hull.fighterBay,
                fighterTubes: hull.fighterTubes,
                squadrons: hull.squadrons.filter { $0.value.total > 0 || $0.value.used > 0 },
                slots: hull.slots,
                turrets: hull.turretHardpoints,
                launchers: hull.launcherHardpoints)

            let selectedStats = summary(of: hull)

            // One stats line per ship, and every effect aimed from one ship at another; the
            // selected ship's `incoming` is the part aimed at it.
            var lines: [FleetSnapshot.Ship] = []
            var effects: [FitSnapshot.Incoming] = []
            for source in ships where present.contains(source) {
                let sourceHull = stats[source.hull]
                if source == selected {
                    lines.append(FleetSnapshot.Ship(id: selected,
                                                    shipTypeID: hull.typeID,
                                                    stats: FleetSnapshot.Ship.Stats(selectedStats)))
                } else {
                    lines.append(FleetSnapshot.Ship(id: source,
                                                    shipTypeID: sourceHull.typeID,
                                                    stats: FleetSnapshot.Ship.Stats(sourceHull)))
                }
                guard isFleet else { continue }
                sourceHull.modules.forEach { module in
                    guard let target = module.target?.pilot, present.contains(target) else { return }
                    let repair = module.repair().flatMap { $0.isRemote ? $0 : nil }
                    let node = module.projectedCapacitorNode()
                    effects.append(FitSnapshot.Incoming(id: .module(module.id),
                                                        pilotID: source,
                                                        targetID: target,
                                                        shipTypeID: sourceHull.typeID,
                                                        typeID: module.typeID,
                                                        count: 1,
                                                        isActive: module.effectiveState >= .active,
                                                        repair: repair,
                                                        capacitor: node.map { $0.averageRecharge - $0.averageDrain }))
                }
                sourceHull.drones.forEach { drone in
                    guard let target = drone.target.map({ PilotID(rawValue: $0.pilot) }),
                          present.contains(target) else { return }
                    let node = drone.projectedCapacitorNode()
                    effects.append(FitSnapshot.Incoming(id: .drone(drone.id),
                                                        pilotID: source,
                                                        targetID: target,
                                                        shipTypeID: sourceHull.typeID,
                                                        typeID: drone.typeID,
                                                        count: drone.count,
                                                        isActive: drone.isActive,
                                                        repair: nil,
                                                        capacitor: node.map { $0.averageRecharge - $0.averageDrain }))
                }
            }
            let incoming = effects.filter { $0.targetID == selected }

            var environment: [TypeID] = []
            stats.environment.forEach { environment.append($0.typeID) }

            // Sorted by slot: entity ids are not allocated in slot order.
            let snapshot = FitSnapshot(pilotID: selected,
                                       shipTypeID: hull.typeID,
                                       modules: modules,
                                       drones: drones,
                                       implants: pilot.implants
                                           .map { FitSnapshot.Implant(id: $0.id, typeID: $0.typeID, slot: $0.slot) }
                                           .sorted { $0.slot < $1.slot },
                                       boosters: pilot.boosters
                                           .map { FitSnapshot.Booster(id: $0.id, typeID: $0.typeID, slot: $0.slot) }
                                           .sorted { $0.slot < $1.slot },
                                       resources: resources,
                                       stats: selectedStats,
                                       warnings: warnings[selected] ?? [],
                                       incoming: incoming,
                                       environment: environment)
            return FleetSnapshot(ships: lines, selected: snapshot, effects: effects)
        })
    }

    /// Reads the stats summary of the hull.
    ///
    /// The capacitor simulation runs once and is passed to `sustainableTank(capacitor:)` rather
    /// than simulated again; the damage figures share the snapshot's `armament`.
    private static func summary(of hull: FitStats.Hull.Snapshot) -> FitStatsSummary {
        let capacitor = hull.capacitor()
        let damage = FitStatsSummary.Damage(dps: hull.dps(),
                                            volley: hull.volleyDamage(),
                                            turrets: hull.dps(from: .turrets),
                                            launchers: hull.dps(from: .launchers),
                                            drones: hull.dps(from: .drones),
                                            fighters: hull.dps(from: .fighters),
                                            otherModules: hull.dps(from: .otherModules))

        // Effective figures depend on the damage pattern, which the editor applies separately
        // (`FitStatsSummary.resonance`).
        return FitStatsSummary(hitPoints: hull.hitPoints,
                               resonance: hull.resonance,
                               resistances: hull.resistances,
                               tank: hull.tank,
                               sustainedTank: hull.sustainableTank(capacitor: capacitor),
                               damage: damage,
                               capacitor: capacitor,
                               navigation: hull.navigation,
                               targeting: hull.targeting,
                               cargoCapacity: hull.cargoCapacity,
                               fuel: FitFuel(hull))
    }
}
