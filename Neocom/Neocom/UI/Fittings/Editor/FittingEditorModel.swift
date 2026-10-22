import DogmaKit
import Foundation
import LiteRow
import Observation
import SDEKit

/// The editor's state: the open ships, the one session that edits them, and the queue that keeps
/// the player's taps in order.
///
/// A single fit is a fleet of one. Every ship is an ordinary `Fitting` record of My Fits; the
/// fleet itself is stored nowhere and lives while the editor is open. The screen never talks to
/// `FitSession` directly: it hands a command here and reads the snapshot back, so nothing but
/// `FitSnapshot` / `FleetSnapshot` crosses this line and the engine's `~Escapable` values never
/// reach a view body.
@Observable
@MainActor
final class FittingEditorModel {
    /// One ship of the fleet: the engine's pilot and the record it is saved to.
    struct Ship: Sendable, Hashable, Identifiable {
        var id: PilotID
        var fittingID: UUID
    }

    /// The fleet's ships, in order. Empty until `load()` or when nothing could be opened.
    private(set) var ships: [Ship] = []
    /// The ship the editor is showing. Every command without a pilot of its own (implants,
    /// boosters, skills) goes to it.
    private(set) var selectedPilot: PilotID?
    /// The selected ship as it is drawn. `nil` means the fit could not be opened at all (an
    /// undecodable blob, or a document the engine refused).
    private(set) var snapshot: FitSnapshot?
    /// One stats line per ship, in fleet order, read with `snapshot`.
    private(set) var fleet: [FleetSnapshot.Ship] = []
    /// Every module and stack of the fleet aimed at another ship, read with `snapshot`. Empty for a
    /// fleet of one.
    private(set) var effects: [FitSnapshot.Incoming] = []
    /// The pilot each ship is calculated for, read from its document on load; changed only through
    /// `setSkills(_:of:)`.
    private(set) var skillsByPilot: [PilotID: FitDocument.Skills] = [:]
    private(set) var isLoading = true
    /// The last command's failure, for an alert. Cleared when the player dismisses it.
    var errorMessage: String?

    /// The selected ship's skills.
    var skills: FitDocument.Skills {
        selectedPilot.flatMap { skillsByPilot[$0] } ?? FitDocument.Skills()
    }

    /// Whether one more ship fits in the engine (`Fit.Pilots.maxCount`), counting those on their
    /// way in.
    var canAddShip: Bool {
        session != nil && ships.count + pendingFittingIDs.count < Fit.Pilots.maxCount
    }

    /// The selected hull's own inventory group and rig size, read once per hull type and kept
    /// alongside the snapshot; `ModulePickerView` needs both on every presentation.
    ///
    /// `nil` before `load()` finishes, and when the SDE read fails.
    private(set) var shipContext: ShipContextRow?
    /// Every type the hull is explicitly named to accept, by type or by group, unioned once here.
    private(set) var allowedTypeIDs: [TypeID] = []
    /// The selected hull's tactical modes, in the switch's order, read with `shipContext`. Empty
    /// for a hull without any.
    private(set) var tacticalModes: [TacticalMode] = []
    /// The damage the effective figures are read against, for the stats screen and the header.
    ///
    /// The editor's own: the fit document has no place for it and it is not an engine command. It
    /// is the same for every ship of the fleet and starts flat.
    var damagePattern: FitDamagePattern = .uniform

    /// The records the editor was opened with, in order.
    @ObservationIgnored private let initialFittingIDs: [UUID]
    @ObservationIgnored private let store: FittingStore
    @ObservationIgnored private let sde: SDEStore
    @ObservationIgnored private var session: FitSession?
    /// The hull type `shipContext` was read for.
    @ObservationIgnored private var contextShipTypeID: TypeID?
    /// Records `addShip(fittingID:)` has queued but the session has not taken in yet, so a second
    /// tap on the same fit, or one past the limit, is refused before it reaches the engine.
    private var pendingFittingIDs: Set<UUID> = []
    /// Each record's environment, as it is to be written. `export(pilot:)` drops the environment,
    /// so every write puts this back. Read from each record on load and replaced for every ship at
    /// once by `setEnvironment(_:)`.
    @ObservationIgnored private var storedEnvironments: [UUID: [FitDocument.Item]] = [:]

    /// The tail of the command queue. Each command awaits this one before it starts: the session is
    /// an actor, which serializes execution but not arrival, so the chain gives the taps their
    /// order.
    @ObservationIgnored private var work: Task<Void, Never>?

    init(fittingIDs: [UUID], store: FittingStore, sde: SDEStore) {
        self.initialFittingIDs = fittingIDs
        self.store = store
        self.sde = sde
    }

    convenience init(fittingID: UUID, store: FittingStore, sde: SDEStore) {
        self.init(fittingIDs: [fittingID], store: store, sde: sde)
    }

    /// The editor is gone: a draft it was opened on that nobody changed or saved goes with it. The
    /// model is the trigger, not the screen's `onDisappear`, which also fires for every screen
    /// pushed over the editor. A command in flight holds the model until it has written.
    isolated deinit {
        for fittingID in initialFittingIDs {
            store.discardDraft(fittingID)
        }
    }

    /// The record a ship is saved to.
    func fittingID(of pilot: PilotID) -> UUID? {
        ships.first { $0.id == pilot }?.fittingID
    }

    /// Whether the record is in the fleet already, or on its way in. One fit cannot be in the fleet
    /// twice: the picker offers it as unavailable.
    func contains(fittingID: UUID) -> Bool {
        pendingFittingIDs.contains(fittingID) || ships.contains { $0.fittingID == fittingID }
    }

    /// Opens the ships: every stored document into the one engine, and the engine's first answer
    /// into `snapshot`.
    ///
    /// A document that cannot be read is left out of the fleet; when none can, or the engine
    /// refuses them, there is no session and no snapshot. The reason is not raised as an alert:
    /// `errorMessage` belongs to commands the player made.
    func load() async {
        defer { isLoading = false }

        var fittingIDs: [UUID] = []
        var documents: [FitDocument] = []
        for fittingID in initialFittingIDs where !fittingIDs.contains(fittingID) {
            guard let document = store.document(of: fittingID) else { continue }
            fittingIDs.append(fittingID)
            documents.append(document)
            storedEnvironments[fittingID] = document.environment
        }
        guard !documents.isEmpty,
              let session = try? await FitSession.load(documents: Array(documents.prefix(Fit.Pilots.maxCount)))
        else { return }
        // Before the session is published, so no command can get in ahead of it.
        await fitMissingModes(session, hulls: documents.compactMap { $0.pilots.first?.ship?.type })

        let pilots = await session.ships
        ships = zip(pilots, fittingIDs).map { Ship(id: $0, fittingID: $1) }
        for (pilot, document) in zip(pilots, documents) {
            skillsByPilot[pilot] = document.pilots.first?.skills ?? FitDocument.Skills()
        }
        selectedPilot = pilots.first
        self.session = session
        await refresh(session)
    }

    // MARK: - Fleet

    /// Shows another ship. The snapshot follows once the commands already queued have run.
    func select(_ pilot: PilotID) {
        guard pilot != selectedPilot, ships.contains(where: { $0.id == pilot }) else { return }
        selectedPilot = pilot
        enqueue { model, session in await model.refresh(session) }
    }

    /// Adds an existing record of My Fits to the fleet and selects it. Writes nothing.
    ///
    /// Refused (`false`) when the record is already in the fleet, the fleet is full, or there is no
    /// session. A record that cannot be read or that the engine refuses ends in `errorMessage`.
    @discardableResult
    func addShip(fittingID: UUID) -> Bool {
        guard canAddShip, !contains(fittingID: fittingID) else { return false }
        guard let document = store.document(of: fittingID) else {
            errorMessage = "This fit's data could not be read."
            return false
        }
        pendingFittingIDs.insert(fittingID)
        enqueue { model, session in
            defer { model.pendingFittingIDs.remove(fittingID) }
            do {
                let pilot = try await session.addShip(document: document)
                if let hull = document.pilots.first?.ship?.type {
                    await model.fitMissingModes(session, hulls: [hull])
                }
                model.ships.append(Ship(id: pilot, fittingID: fittingID))
                model.storedEnvironments[fittingID] = document.environment
                model.skillsByPilot[pilot] = document.pilots.first?.skills ?? FitDocument.Skills()
                model.selectedPilot = pilot
            } catch {
                model.errorMessage = Self.message(for: error)
            }
            await model.refresh(session)
        }
        return true
    }

    /// Takes a ship out of the fleet; its record is not touched and the session clears the targets
    /// the other ships had on it. The last ship cannot be removed.
    ///
    /// `ships` drops it right away, so a later command for it is refused at the door; commands
    /// queued before it still run and are saved, each having resolved its record when queued.
    func removeShip(_ pilot: PilotID) {
        guard ships.count > 1, let index = ships.firstIndex(where: { $0.id == pilot }) else { return }
        ships.remove(at: index)
        skillsByPilot[pilot] = nil
        if selectedPilot == pilot {
            selectedPilot = ships[min(index, ships.count - 1)].id
        }
        enqueue { model, session in
            await session.removeShip(pilot)
            await model.refresh(session)
        }
    }

    /// Aims a module at another ship, or at nothing. Writes nothing: a target is not part of any
    /// document.
    func setTarget(_ target: PilotID?, of id: ModuleID) {
        guard isInFleet(id.hull.pilot) else { return }
        run(saving: nil) { session in await session.setTarget(target, of: id) }
    }

    /// The drone stack twin of `setTarget(_:of:)` for a module.
    func setTarget(_ target: PilotID?, of id: DroneID) {
        guard isInFleet(id.hull.pilot) else { return }
        run(saving: nil) { session in await session.setTarget(target, of: id) }
    }

    // MARK: - Skills

    /// Replaces a ship's whole skill set: the one entry point for every skills change. `nil` is the
    /// selected ship.
    ///
    /// `skillsByPilot` is updated before the command has run, so a stepper tapped twice in a row
    /// computes its second value from the first. The command carries the full set because `default`
    /// and `levels` only mean something read together.
    func setSkills(_ newSkills: FitDocument.Skills, of pilot: PilotID? = nil) {
        guard let pilot = pilot ?? selectedPilot, isInFleet(pilot),
              newSkills != skillsByPilot[pilot] else { return }
        skillsByPilot[pilot] = newSkills
        perform(on: pilot) { session in await session.setSkills(newSkills, of: pilot) }
    }

    // MARK: - Implants and boosters

    /// The implant and booster commands, one wrapper each, all through `perform(on:_:)`. The slot
    /// is the key, and a pick in an occupied slot is `setImplant` / `setBooster`, never `remove`
    /// then `add` from the screen: that would be two commands and two snapshots.
    ///
    /// `pilot: nil` is the selected ship, resolved when the call is made.

    func add(implant typeID: TypeID, to pilot: PilotID? = nil) {
        guard let pilot = pilot ?? selectedPilot else { return }
        perform(on: pilot) { session in try await session.add(implant: typeID, to: pilot) }
    }

    func add(booster typeID: TypeID, to pilot: PilotID? = nil) {
        guard let pilot = pilot ?? selectedPilot else { return }
        perform(on: pilot) { session in try await session.add(booster: typeID, to: pilot) }
    }

    func remove(implantIn slot: UInt16, of pilot: PilotID? = nil) {
        guard let pilot = pilot ?? selectedPilot else { return }
        perform(on: pilot) { session in await session.remove(implantIn: slot, of: pilot) }
    }

    func remove(boosterIn slot: UInt16, of pilot: PilotID? = nil) {
        guard let pilot = pilot ?? selectedPilot else { return }
        perform(on: pilot) { session in await session.remove(boosterIn: slot, of: pilot) }
    }

    func setImplant(_ typeID: TypeID, inSlot slot: UInt16, of pilot: PilotID? = nil) {
        guard let pilot = pilot ?? selectedPilot else { return }
        perform(on: pilot) { session in try await session.setImplant(typeID, inSlot: slot, of: pilot) }
    }

    func setBooster(_ typeID: TypeID, inSlot slot: UInt16, of pilot: PilotID? = nil) {
        guard let pilot = pilot ?? selectedPilot else { return }
        perform(on: pilot) { session in try await session.setBooster(typeID, inSlot: slot, of: pilot) }
    }

    /// The preset (`boosters: nil`, implants only) and `CLEAR` (both empty): one command, one
    /// snapshot, one write. `nil` leaves a list as it is.
    func setPilotItems(implants: [TypeID]?, boosters: [TypeID]?, of pilot: PilotID? = nil) {
        guard let pilot = pilot ?? selectedPilot else { return }
        perform(on: pilot) { session in
            await session.setPilotItems(implants: implants, boosters: boosters, of: pilot)
        }
    }

    // MARK: - Mutations

    /// The mutation commands, each on the module's own ship through `perform(on:_:)`; the document
    /// carries the mutaplasmid and the rolls.

    func mutate(_ id: ModuleID, with mutaplasmidID: TypeID) {
        perform(on: id.hull.pilot) { session in try await session.mutate(id, with: mutaplasmidID) }
    }

    /// One command per committed slider, never one per frame of the drag.
    func setRoll(_ value: Double, for attributeID: AttributeID, of id: ModuleID) {
        perform(on: id.hull.pilot) { session in try await session.setRoll(value, for: attributeID, of: id) }
    }

    func resetRolls(of id: ModuleID) {
        perform(on: id.hull.pilot) { session in await session.resetRolls(of: id) }
    }

    func demutate(_ id: ModuleID) {
        perform(on: id.hull.pilot) { session in try await session.demutate(id) }
    }

    // MARK: - Environment

    /// Replaces the system effects the fleet is calculated under; the screen sends one effect or
    /// none. Queued like every other command.
    ///
    /// Writes every ship rather than the one it touched, since the environment is the whole
    /// engine's. The ships are the ones in the fleet when the command runs. A refusal changes
    /// nothing (the session puts the old effects back).
    ///
    /// Not compared with `snapshot.environment`: a pick queued behind another has not reached the
    /// snapshot yet, so `None` right after an effect would be dropped as a no-op.
    func setEnvironment(_ typeIDs: [TypeID]) {
        guard session != nil else { return }
        enqueue { model, session in
            do {
                try await session.setEnvironment(typeIDs)
            } catch {
                model.errorMessage = Self.message(for: error)
                await model.refresh(session)
                return
            }
            await model.refresh(session)
            let items = typeIDs.map { FitDocument.Item($0) }
            for ship in model.ships {
                model.storedEnvironments[ship.fittingID] = items
                await model.write(ship.id, to: ship.fittingID, from: session)
            }
        }
    }

    // MARK: - The command queue

    /// Runs one command that edits `pilot`'s ship, in turn after everything already queued, and
    /// then writes that ship, and only that ship, back to its record. The other ships' figures may
    /// change (a target), their documents do not.
    ///
    /// The command must touch `pilot` and nothing else: a module or drone command is performed on
    /// `id.hull.pilot`, everything else names its pilot explicitly. A pilot no longer in the fleet
    /// is refused here.
    ///
    /// Whether the command succeeded or threw, what the engine holds afterwards is published and
    /// written back. A failure is not a rollback: `DogmaEngine.edit` keeps whatever the closure did
    /// before it threw, and `replace(_:with:)` removes the old module before adding the new one, so
    /// a refused `add` leaves the fit one module short. Keeping the last good snapshot would draw a
    /// module the engine no longer has; the reason goes to the alert instead.
    func perform(on pilot: PilotID, _ command: @escaping @Sendable (FitSession) async throws -> Void) {
        // The record is resolved now, not when the command runs: a `removeShip` made after this
        // call drops the ship from `ships` at once, while this command's edit still has to reach
        // the store.
        guard let fittingID = fittingID(of: pilot) else { return }
        run(saving: (pilot: pilot, fittingID: fittingID), command)
    }

    private func isInFleet(_ pilot: PilotID) -> Bool {
        ships.contains { $0.id == pilot }
    }

    /// The one place a command meets the store: `saving` is the ship it writes, or `nil` for a
    /// command that changes no document (a target). One command, at most one write.
    private func run(saving: (pilot: PilotID, fittingID: UUID)?,
                     _ command: @escaping @Sendable (FitSession) async throws -> Void) {
        enqueue { model, session in
            do {
                try await command(session)
            } catch {
                // `DogmaError` is the engine's own reason; `message(for:)` gives it English words.
                // Raised before the re-read so the alert does not wait on a second trip into the
                // engine.
                model.errorMessage = Self.message(for: error)
            }
            // The engine is the truth even when it refused: publish what it holds and save the
            // touched ship.
            await model.refresh(session)
            if let saving {
                await model.write(saving.pilot, to: saving.fittingID, from: session)
            }
        }
    }

    /// Appends a step to the queue. Every change to the engine goes through here, so changes reach
    /// the session in the order they were made.
    private func enqueue(_ step: @escaping @MainActor (FittingEditorModel, FitSession) async -> Void) {
        guard let session else { return }
        let previous = work
        // `self` is captured strongly on purpose: a command that has reached the engine has to make
        // it to the store even if the screen closed. The task is short and ends on its own.
        work = Task {
            // Only the point in time: the previous command has published its snapshot, and its
            // failure is not this one's.
            _ = await previous?.result
            await step(self, session)
        }
    }

    /// Publishes the selected ship and the fleet's lines.
    ///
    /// Published before anything is exported: the export is a second trip into the engine, and rows
    /// compute their next command from what they show, so a lagging snapshot gives a fast second
    /// tap a stale number.
    private func refresh(_ session: FitSession) async {
        guard let selected = selectedPilot,
              let fleet = await session.snapshot(selected: selected),
              // The selection moved while the engine was answering: the step `select` queued
              // publishes the new one.
              selected == selectedPilot
        else { return }
        snapshot = fleet.selected
        self.fleet = fleet.ships
        effects = fleet.effects
        if fleet.selected.shipTypeID != contextShipTypeID {
            await loadShipContext(for: fleet.selected.shipTypeID)
        }
    }

    /// Writes one ship back to its record: the only store write the editor makes.
    private func write(_ pilot: PilotID, to fittingID: UUID, from session: FitSession) async {
        guard let document = await export(pilot, of: fittingID, from: session) else { return }
        store.save(document, to: fittingID)
    }

    /// One ship's document as the engine holds it, with its stored environment put back. `nil` for
    /// a pilot the engine no longer holds: it would export as an empty document and erase the fit.
    private func export(_ pilot: PilotID, of fittingID: UUID, from session: FitSession) async -> FitDocument? {
        // Read at export time so a rename in between reaches the document; `FittingStore.save`
        // writes the `name` column into the blob anyway.
        let name = store.summary(of: fittingID)?.name
        var document = await session.export(pilot: pilot, name: name)
        document.environment = storedEnvironments[fittingID] ?? []
        return document.pilots.isEmpty ? nil : document
    }

    /// The ship's document as it is on screen, for "Upload to EVE": exported from this screen's own
    /// session, queued behind every command already sent. Never a second session on the fit (see
    /// `FitSession`). `nil` when the record is not a ship of this fleet or there is no session.
    func currentDocument(of fittingID: UUID) async -> FitDocument? {
        guard session != nil, let pilot = ships.first(where: { $0.fittingID == fittingID })?.id else { return nil }
        return await withCheckedContinuation { continuation in
            enqueue { model, session in
                continuation.resume(returning: await model.export(pilot, of: fittingID, from: session))
            }
        }
    }

    // MARK: - Reads

    /// The attribute values the engine holds for one fitted item, for the item screen's "In Fit"
    /// reading. Empty when there is no session.
    ///
    /// Not queued behind `work` and not routed through `perform`: it changes nothing, and the info
    /// screen must not wait on edits or hold a `FitSession`.
    func attributes(of target: FitInfoTarget, ids: [AttributeID]) async -> [AttributeID: Double] {
        guard let session else { return [:] }
        switch target {
        case let .module(id): return await session.attributes(of: id, ids: ids)
        case let .charge(id): return await session.attributes(ofChargeIn: id, ids: ids)
        case let .drone(id): return await session.attributes(of: id, ids: ids)
        case let .ship(pilot): return await session.attributes(ofHullOf: pilot, ids: ids)
        case let .implant(id, pilot): return await session.attributes(of: id, of: pilot, ids: ids)
        case let .booster(id, pilot): return await session.attributes(of: id, of: pilot, ids: ids)
        }
    }

    /// What the engine holds for each booster of the selected ship, for the implants screen's side
    /// effects: the penalty attributes with the pilot's skills applied. Empty when there is no
    /// session.
    ///
    /// Unlike the two reads above it waits for the commands already queued: `setSkills` updates
    /// `skills` here before the engine has them, and a read that did not wait would answer for the
    /// old skills and never be asked again.
    func attributesOfBoosters(ids: [AttributeID]) async -> [BoosterID: [AttributeID: Double]] {
        guard let session else { return [:] }
        _ = await work?.result
        guard let pilot = selectedPilot else { return [:] }
        return await session.attributesOfBoosters(of: pilot, ids: ids)
    }

    /// What the engine holds for one fitted item, for its sheet's digest panel. Empty when there is
    /// no session. Not queued, for the same reasons as `attributes(of:ids:)`.
    func digest(of subject: FitItemSubject) async -> FitItemDigest {
        guard let session else { return FitItemDigest() }
        switch subject {
        case let .module(id): return await session.digest(of: id)
        case let .drone(id): return await session.digest(of: id)
        }
    }

    // MARK: - SDE context

    /// Reads the hull's rig size and the two "explicitly allowed" lists once per hull type;
    /// `ModulePickerView` must not run these queries itself.
    ///
    /// Both fetches share one `read`: the group query needs the hull's own inventory group, which
    /// only the context row carries.
    private func loadShipContext(for shipTypeID: TypeID) async {
        contextShipTypeID = shipTypeID
        // Another hull's filters would be wrong for this one; none at all is only incomplete.
        shipContext = nil
        allowedTypeIDs = []
        tacticalModes = []

        await sde.load()
        guard case let .ready(database) = sde.state else { return }

        let contextQuery = FittingBrowser.shipContext(shipTypeID)
        let byTypeQuery = FittingBrowser.allowedByShipType(shipTypeID)
        let hullQuery = FittingBrowser.ships([shipTypeID])
        let modesQuery = FittingBrowser.tacticalModes(of: shipTypeID)

        let result = try? await database.database.read { reader -> (ShipContextRow?, [TypeID], [TacticalMode]) in
            let context = try reader.fetchOne(contextQuery)
            var allowed = Set(try reader.fetchAll(byTypeQuery).map(\.id))
            if let context {
                let byGroupQuery = FittingBrowser.allowedByShipGroup(context.groupID)
                allowed.formUnion(try reader.fetchAll(byGroupQuery).map(\.id))
            }
            // The switch's modes, with their bonuses; three rows at most.
            let modeRows = try reader.fetchAll(modesQuery)
            var modes: [TacticalMode] = []
            if !modeRows.isEmpty {
                let attributes = try reader.fetchAll(FittingBrowser.tacticalModeAttributes(of: modeRows.map(\.id)))
                let hullName = try reader.fetchOne(hullQuery)?.name ?? ""
                modes = TacticalMode.modes(rows: modeRows, attributes: attributes, hullName: hullName)
            }
            return (context, Array(allowed), modes)
        }

        // Another hull was selected while this one was being read.
        guard let (context, allowed, modes) = result, contextShipTypeID == shipTypeID else { return }
        shipContext = context
        allowedTypeIDs = allowed
        tacticalModes = modes
    }

    /// A hull with tactical modes always flies one: a new fit, or a document saved without one,
    /// gets the first of its modes as it is opened. In the engine only: nothing is written, so
    /// opening a draft does not store it.
    private func fitMissingModes(_ session: FitSession, hulls: [TypeID]) async {
        guard !hulls.isEmpty else { return }
        await sde.load()
        guard case let .ready(database) = sde.state else { return }
        let query = FittingBrowser.tacticalModes(ofHulls: Set(hulls).sorted { $0.rawValue < $1.rawValue })
        guard let rows = try? await database.database.read({ reader in try reader.fetchAll(query) }) else { return }
        // In type id order, so the first row of a hull is its first mode.
        var defaults: [TypeID: TypeID] = [:]
        for row in rows where defaults[row.hullID] == nil {
            defaults[row.hullID] = row.modeID
        }
        guard !defaults.isEmpty else { return }
        await session.fitMissingModes(defaults)
    }

    // MARK: - Engine errors, in English

    /// Turns the engine's refusal into a sentence the alert can show. `DogmaError` is not
    /// `LocalizedError`, and a retroactive conformance is refused by the compiler; unhandled,
    /// `error.localizedDescription` is Foundation's placeholder.
    ///
    /// Covers every case the editor's commands can reach. `setCharge(_:of:)` throws `cantFit` both
    /// for a module the hull refuses and a charge the module refuses, so its wording says "here".
    /// `typeLimitExceeded` and `groupLimitExceeded` are not thrown today: `maxTypeFitted` and
    /// `maxGroupFitted` are reported, not enforced. `implantSlotOccupied` is reached only by `add`
    /// into a taken cell; `boosterSlotOccupied` by both `add` and a replacement, since a booster
    /// takes the slot its type names. `attributeNotFound` means an implant-category item has no
    /// slot of the requested kind: a booster given to the implant command or the reverse. The
    /// mutation errors mean a database out of step with the engine, a roll without a range, or a
    /// roll edit arriving after the mutation was removed. `noSlot` is a type the engine cannot
    /// place in any rack (Lux Kontos, Upwell Quantum Cores).
    private static func message(for error: any Error) -> String {
        guard let dogmaError = error as? DogmaError else { return error.localizedDescription }
        switch dogmaError {
        case .cantFit:
            return "This item cannot be fitted here."
        case .typeNotFound:
            return "This item is missing from the database. The static data export may be out of date."
        case .invalidCategory:
            return "This item is not something that can be fitted here."
        case .entityLimitExceeded:
            return "This fit already holds as many items as can be calculated."
        case .rigSizeMismatch:
            return "This rig's size does not match the ship's rig slots."
        case .subsystemSlotOccupied:
            return "That subsystem slot is already occupied. Remove the current subsystem first."
        case .subsystemsNotSupported:
            return "This ship does not support subsystems."
        case .groupLimitExceeded:
            return "The ship already carries the maximum number of modules from this group."
        case .typeLimitExceeded:
            return "The ship already carries the maximum number of this module."
        case .implantSlotOccupied:
            return "That implant slot is already occupied. Remove the current implant first."
        case .boosterSlotOccupied:
            // The player picked no slot: the booster named its own, and one already fitted holds
            // it.
            return "Another booster is already fitted in the slot this one needs. Tap that booster to replace it, or remove it first."
        case .attributeNotFound:
            return "This item does not belong in that slot."
        case .pilotLimitExceeded:
            return "The fleet already has as many ships as can be calculated together."
        case .mutaplasmidNotFound:
            return String(localized: "This mutaplasmid is missing from the database. The static data export may be out of date.")
        case .mutaplasmidNotApplicable:
            return String(localized: "This mutaplasmid cannot be applied to this module.")
        case .attributeNotMutable:
            return String(localized: "This mutaplasmid does not change that attribute.")
        case .notMutated:
            return String(localized: "This module is no longer mutated.")
        case .noSlot:
            // A type with no slot effect: no rack takes it. The picker never offers one; an
            // imported fit can carry it.
            return String(localized: "This item cannot be fitted into any slot.")
        }
    }
}
