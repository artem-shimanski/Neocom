import DogmaKit
import SwiftUI

/// Which fitted thing a sheet, or a picker opened from one, is about. Ids rather than a copy of
/// the row: the sheet looks its subject up in the current snapshot on every render, so changes
/// made from inside it show at once.
enum FitItemSubject: Hashable, Identifiable {
    case module(ModuleID)
    case drone(DroneID)

    var id: Self { self }
}

/// What one module, rig, subsystem or drone stack is in this fit, and what can be done to it:
/// the sheet a tap on its row opens.
///
/// One view with three sets of rows: a state segment for a module, a count and an "in space"
/// switch for a drone, nothing for a rig, with different actions; the header and the digest card
/// are shared. It presents nothing itself: an action that leads somewhere is handed back to
/// `FittingEditorSections`, which closes this sheet first, since two presentations started in
/// one turn race and the second loses silently.
struct FitItemSheet: View {
    let subject: FitItemSubject
    /// The current snapshot, not the one the sheet opened with; see `FitItemSubject`.
    let snapshot: FitSnapshot
    /// Names for every type the snapshot mentions, read once by the editor's own query.
    let names: [TypeID: String]
    /// The set the fit is calculated for, for the last segment of the caption.
    let skills: FitDocument.Skills
    /// The ships of the fleet, in fleet order; empty for a fleet of one, where there is no target
    /// row.
    var fleet: [FleetMember] = []
    /// Asks the editor's model for what the engine holds for this item. Read when the sheet opens
    /// and when the item's own facts change, not on every snapshot.
    let digest: (FitItemSubject) async -> FitItemDigest
    /// A pick in the target sheet; `nil` is "No Target".
    var onSetTarget: (FitItemSubject, PilotID?) -> Void = { _, _ in }
    let onSetState: (ModuleID, Entity.Module.State) -> Void
    let onSetDroneCount: (DroneID, Int) -> Void
    let onSetDroneActive: (DroneID, Bool) -> Void
    /// "Ammo…": the module as it is now; its charge groups and size filter the picker.
    let onRequestAmmo: (FitSnapshot.Module) -> Void
    /// "Ammo Info" names the module only: the host reads the loaded charge from its snapshot.
    let onShowAmmoInfo: (ModuleID) -> Void
    let onApplyAmmoToAll: (FitSnapshot.Module) -> Void
    let onRemoveAmmo: (ModuleID) -> Void
    /// "Variations…" and "Info" name only the subject: the host builds the request or route.
    let onRequestVariations: (FitItemSubject) -> Void
    let onShowInfo: (FitItemSubject) -> Void
    let onRemove: (FitItemSubject) -> Void
    /// The module types of the fit some mutaplasmid applies to; `Mutate…` is offered for these.
    var mutableTypeIDs: Set<TypeID> = []
    /// `Mutate…` and `Edit Mutation…`: the mutation screen, which the host pushes.
    var onShowMutation: (ModuleID) -> Void = { _ in }
    var onRemoveMutation: (ModuleID) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.trainingContext) private var trainingContext
    @Environment(AccountStore.self) private var accounts

    /// What the engine holds for the subject. Empty until the first read comes back; the card is
    /// not drawn then.
    @State private var values = FitItemDigest()
    /// The count the player has asked for while the engine catches up: the stepper's auto-repeat
    /// outruns the snapshot.
    @State private var pendingCount: Int?
    /// Whether the target picker is open: a sheet over this sheet that closes itself on a pick.
    @State private var isPickingTarget = false

    /// Tall enough that the actions are reachable without scrolling, short enough that the fit
    /// stays visible behind it; `.large` stays available for the longest digests.
    private static let detents: Set<PresentationDetent> = [.fraction(0.75), .large]

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents(Self.detents)
        .sheet(isPresented: $isPickingTarget) { targetSheet }
        // Keyed on the item's own facts, not the snapshot: every edit rebuilds the snapshot and the
        // digest is a trip into the engine. The key is the state, the charge, the type, a drone's
        // stack and a mutation's rolls; edits elsewhere in the fit that move these numbers are not
        // followed.
        .task(id: digestKey) {
            values = await digest(subject)
        }
        .onChange(of: droneCount) { _, newCount in
            if pendingCount == newCount { pendingCount = nil }
        }
    }

    // MARK: - The subject, looked up now

    private var module: FitSnapshot.Module? {
        guard case let .module(id) = subject else { return nil }
        return snapshot.modules.first { $0.id == id }
    }

    private var drone: FitSnapshot.Drone? {
        guard case let .drone(id) = subject else { return nil }
        return snapshot.drones.first { $0.id == id }
    }

    /// What the digest depends on. A struct so that adding a field is a compiler-checked change.
    private struct DigestKey: Hashable {
        var subject: FitItemSubject
        var typeID: TypeID?
        var state: Entity.Module.State?
        var effectiveState: Entity.Module.State?
        var charge: TypeID?
        var count: Int?
        var isActive: Bool?
        /// A roll moved on the mutation screen changes every figure of the module.
        var rolls: [Double]?
    }

    private var digestKey: DigestKey {
        DigestKey(subject: subject,
                  typeID: module?.typeID ?? drone?.typeID,
                  state: module?.state,
                  effectiveState: module?.effectiveState,
                  charge: module?.charge,
                  count: drone?.count,
                  isActive: drone?.isActive,
                  rolls: module?.mutation?.rolls.map(\.value))
    }

    private var droneCount: Int? { drone?.count }

    @ViewBuilder
    private var content: some View {
        if let module {
            moduleSheet(module)
        } else if let drone {
            droneSheet(drone)
        } else {
            // The item is no longer in the fit; every path that removes one closes this sheet.
            Color.clear
        }
    }

    // MARK: - A module, a rig or a subsystem

    private func moduleSheet(_ module: FitSnapshot.Module) -> some View {
        HUDActionSheet(
            title: Text(verbatim: names[module.typeID] ?? ""),
            subtitle: Text(verbatim: caption(for: module)),
            groups: actions(for: module),
            icon: { HUDItemIcon(typeID: module.typeID, size: HUDActionSheetMetrics.iconSize) }
        ) {
            // A rig or a subsystem tops out at `.offline`: no segment, as the row draws no control.
            if module.maxAllowedState > .offline {
                Section {
                    statePicker(module)
                        .hudBareRow()
                }
            }
            if module.isProjectable, let row = targetRow(current: module.target) {
                HUDListSection { row }
            }
            digestCard(rows: rows(for: module), damage: nil)
        }
    }

    private func statePicker(_ module: FitSnapshot.Module) -> some View {
        Picker("Module State", selection: Binding(get: { module.state },
                                                  set: { onSetState(module.id, $0) })) {
            // `State` is a `UInt8` ladder; the type's ceiling is a value on it, the same cap the
            // row's control obeys.
            ForEach(Entity.Module.State.ladder(upTo: module.maxAllowedState), id: \.self) { state in
                Text(verbatim: state.title).tag(state)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// `<SLOT> · <STATE> · <charge> · <skills set>`, with the sheet's slot names ("HIGH SLOT", not
    /// the section headings' "HIGH").
    private func caption(for module: FitSnapshot.Module) -> String {
        var parts = [module.slot.captionName]
        if module.maxAllowedState > .offline {
            parts.append(module.state.title)
        }
        if let charge = module.charge, let name = names[charge] {
            parts.append(name)
        }
        parts.append(skillsLabel)
        return parts.joined(separator: " · ")
    }

    private func actions(for module: FitSnapshot.Module) -> [[HUDAction]] {
        let typeName = names[module.typeID] ?? ""
        // Charge actions only for a type that takes one; `HUDActionList` drops the empty group.
        var ammo: [HUDAction] = []
        if !module.chargeGroups.isEmpty {
            ammo.append(HUDAction("Ammo…", systemImage: "line.3.horizontal.decrease") {
                onRequestAmmo(module)
            })
            if module.charge != nil {
                ammo.append(HUDAction("Ammo Info", systemImage: "info.circle") {
                    onShowAmmoInfo(module.id)
                })
                // "Apply to all" with one module of this type would apply the charge to its own
                // module.
                if snapshot.modules.count(where: { $0.typeID == module.typeID }) > 1 {
                    ammo.append(HUDAction(title: Text("Apply Ammo to All \(typeName)"),
                                          systemImage: "square.grid.2x2") {
                        onApplyAmmoToAll(module)
                    })
                }
                ammo.append(HUDAction("Remove Ammo", systemImage: "minus.circle") {
                    onRemoveAmmo(module.id)
                })
            }
        }
        // A mutated module has no variations: its type is the mutaplasmid's result. The mutation is
        // edited or taken off instead.
        var item: [HUDAction] = []
        if module.mutation != nil {
            item.append(HUDAction("Edit Mutation…", systemImage: "wand.and.sparkles") {
                onShowMutation(module.id)
            })
            item.append(HUDAction("Remove Mutation", systemImage: "minus.circle") {
                onRemoveMutation(module.id)
            })
        } else {
            item.append(HUDAction("Variations…", systemImage: "arrow.left.arrow.right") {
                onRequestVariations(subject)
            })
            if mutableTypeIDs.contains(module.typeID) {
                item.append(HUDAction("Mutate…", systemImage: "wand.and.sparkles") {
                    onShowMutation(module.id)
                })
            }
        }
        item.append(HUDAction("Info", systemImage: "info.circle") { onShowInfo(subject) })
        return [
            ammo,
            item,
            // Last and on its own: removal has no confirmation or undo, so it stays away from the
            // thumb.
            [HUDAction("Remove", systemImage: "trash", role: .destructive) { onRemove(subject) }],
        ]
    }

    // MARK: - A drone stack

    private func droneSheet(_ drone: FitSnapshot.Drone) -> some View {
        HUDActionSheet(
            title: Text(verbatim: names[drone.typeID] ?? ""),
            subtitle: Text(verbatim: caption(for: drone)),
            groups: [
                // Info first for a drone, then Variations….
                [
                    HUDAction("Info", systemImage: "info.circle") { onShowInfo(subject) },
                    HUDAction("Variations…", systemImage: "arrow.left.arrow.right") {
                        onRequestVariations(subject)
                    },
                ],
                [HUDAction("Remove", systemImage: "trash", role: .destructive) { onRemove(subject) }],
            ],
            icon: { HUDItemIcon(typeID: drone.typeID, size: HUDActionSheetMetrics.iconSize) }
        ) {
            stackControls(drone)
            // Only a drone's digest carries its damage split.
            digestCard(rows: rows(for: drone), damage: values.dps)
        }
    }

    private func stackControls(_ drone: FitSnapshot.Drone) -> some View {
        let count = pendingCount ?? drone.count
        return HUDListSection {
            HStack(spacing: 12) {
                Text("Count")
                    .font(.hudSheetBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "\(count) / \(drone.maxCount)")
                    .font(.hudReadout)
                    .foregroundStyle(Color.hudInkMuted)
                Stepper("Count", value: Binding(get: { count }, set: { newCount in
                    pendingCount = newCount
                    onSetDroneCount(drone.id, newCount)
                }), in: 1...drone.maxCount)
                    .labelsHidden()
                    .fixedSize()
            }
            .hudRow(.sheet)

            Toggle("In Space", isOn: Binding(get: { drone.isActive },
                                             set: { onSetDroneActive(drone.id, $0) }))
                .disabled(!snapshot.canLaunch(drone))
                .font(.hudSheetBody)
                .hudRow(.sheet)

            if drone.isProjectable, let row = targetRow(current: drone.target) {
                row
            }
        }
    }

    // MARK: - The target

    private var candidates: [FleetMember] { fleet.filter { $0.id != snapshot.pilotID } }

    /// "Target — <ship>|No Target ›", opening the picker. `nil` when there is nobody to aim at.
    private func targetRow(current: PilotID?) -> AnyView? {
        guard fleet.count > 1 else { return nil }
        let name = current.flatMap { id in fleet.first { $0.id == id }?.name }
        return AnyView(
            Button { isPickingTarget = true } label: {
                HStack(spacing: 12) {
                    Text("Target")
                        .font(.hudSheetBody)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    (name.map { Text(verbatim: $0) } ?? Text("No Target"))
                        .font(.hudReadout)
                        .foregroundStyle(name == nil ? Color.hudInkMuted : Color.hudOk)
                        .lineLimit(1)
                    HUDChevron()
                }
                .hudRow(.sheet)
            }
            .hudRowButton(.sheet)
            .accessibilityHint("Chooses the ship of the fleet this is aimed at")
        )
    }

    @ViewBuilder
    private var targetSheet: some View {
        let current: PilotID? = switch subject {
        case .module: module?.target
        case .drone: drone?.target
        }
        FitTargetSheet(itemName: (module?.typeID ?? drone?.typeID).flatMap { names[$0] } ?? "",
                       current: current,
                       candidates: candidates,
                       hullNames: names,
                       onSelect: { onSetTarget(subject, $0) })
    }

    /// `DRONE · N IN SPACE|IN BAY · <skills set>`: a stack has no slot and no state ladder.
    private func caption(for drone: FitSnapshot.Drone) -> String {
        let count = pendingCount ?? drone.count
        let deployment = drone.isActive
            ? String(localized: "\(count) in space")
            : String(localized: "\(count) in bay")
        let kind = drone.isFighter ? String(localized: "Fighter") : String(localized: "Drone")
        return [kind, deployment, skillsLabel].joined(separator: " · ")
    }

    // MARK: - The digest

    /// The engine's figures for the subject as leader rows, plus a drone's damage split. Drawn only
    /// once there is something to draw: no card for a digest that has not come back or is empty.
    @ViewBuilder
    private func digestCard(rows: [DigestRow], damage: DamageVector?) -> some View {
        if !rows.isEmpty || damage != nil {
            HUDListSection {
                ForEach(rows) { row in
                    HUDReadoutRow(row.label, value: row.value)
                }
                if let damage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Damage Types")
                            .font(.hudMicro)
                            .tracking(1.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                        HUDDamageBlock(damage, scale: .sum, numbers: .percent, isToggleable: true)
                    }
                    .hudRow()
                }
            }
        }
    }

    /// One row of the digest. Keyed by its label, which is unique within a card.
    private struct DigestRow: Identifiable {
        var label: LocalizedStringKey
        var value: String
        var id: String
    }

    private func rows(for module: FitSnapshot.Module) -> [DigestRow] {
        var rows = RowBuilder()
        // A row appears because the engine gave a figure for it: a turret shows no repair rate.
        if let dps = values.dps {
            rows.add("DPS", FitStatFormat.dpsFigure(dps.sum()))
        }
        if let volley = values.volley {
            rows.add("Volley", FitStatFormat.plain(volley.sum()))
        }
        if let cycle = values.cycleTime {
            // The cycle goes by the name of what it belongs to: a weapon's is its rate of fire.
            rows.add(values.dps != nil ? "Rate of Fire" : "Cycle Time", FitStatFormat.seconds(cycle))
        }
        addRange(to: &rows)
        if let tracking = values.accuracyScore {
            rows.add("Tracking", FitStatFormat.plain(tracking, fraction: 0...2))
        }
        if let repair = values.repair {
            rows.add(Self.label(of: repair), FitStatFormat.hpPerSecond(repair.hpPerSecond))
        }
        if let mining = values.miningYield {
            rows.add("Mining Yield", "\(FitStatFormat.m³(mining))/s")
        }
        if let bonus = values.speedBonus {
            rows.add("Max Velocity Bonus", "+\(FitStatFormat.percent(bonus))")
        }
        if let capacitor = values.capacitorUse {
            rows.add("Capacitor", FitStatFormat.energyUse(capacitor))
        }
        if let reload = values.reloadTime {
            rows.add("Reload", FitStatFormat.seconds(reload))
        }
        // One row for both: the two numbers read together; a module that spends neither gets
        // neither.
        if values.cpu != nil || values.powerGrid != nil {
            let cpu = FitStatFormat.plain(values.cpu ?? 0, fraction: 0...1)
            let power = FitStatFormat.plain(values.powerGrid ?? 0, fraction: 0...1)
            rows.add("CPU / Powergrid", "\(cpu) tf / \(power) MW")
        }
        if let calibration = values.calibration {
            rows.add("Calibration", FitStatFormat.plain(calibration, fraction: 0...0))
        }
        // What a subsystem gives rather than spends. Positive only: modifiers are additive, and
        // zero is a slot the subsystem has nothing to say about.
        let granted: [(LocalizedStringKey, Double?)] = [
            ("High Slots", values.hiSlots),
            ("Medium Slots", values.medSlots),
            ("Low Slots", values.lowSlots),
            ("Turret Hardpoints", values.turretHardpoints),
            ("Launcher Hardpoints", values.launcherHardpoints),
        ]
        for (label, value) in granted {
            if let value {
                rows.add(label, "+\(FitStatFormat.plain(value, fraction: 0...0))")
            }
        }
        return rows.rows
    }

    private func rows(for drone: FitSnapshot.Drone) -> [DigestRow] {
        var rows = RowBuilder()
        if let dps = values.dps {
            // The engine's DPS is the whole stack's; the per-drone figure is what compares drone
            // types.
            rows.add("DPS", FitStatFormat.dpsFigure(dps.sum()))
            if drone.count > 1 {
                rows.add(drone.isFighter ? "DPS per Fighter" : "DPS per Drone",
                         FitStatFormat.dpsFigure(dps.sum() / Double(drone.count)))
            }
        }
        if let volley = values.volley {
            rows.add("Volley", FitStatFormat.plain(volley.sum()))
        }
        if let cycle = values.cycleTime {
            rows.add("Rate of Fire", FitStatFormat.seconds(cycle))
        }
        addRange(to: &rows)
        if let tracking = values.accuracyScore {
            rows.add("Tracking", FitStatFormat.plain(tracking, fraction: 0...2))
        }
        if let mining = values.miningYield {
            rows.add("Mining Yield", "\(FitStatFormat.m³(mining))/s")
        }
        if let velocity = values.maxVelocity {
            rows.add("Max Velocity", FitStatFormat.speed(velocity))
        }
        // Per drone, not per stack: the stack's volume and bandwidth are the hull's budget, drawn
        // in the header.
        if let volume = values.volumePerDrone {
            rows.add(drone.isFighter ? "Volume per Fighter" : "Volume per Drone", FitStatFormat.m³(volume))
        }
        if let bandwidth = values.bandwidthPerDrone {
            rows.add("Bandwidth per Drone", "\(FitStatFormat.plain(bandwidth, fraction: 0...0)) Mbit/s")
        }
        return rows.rows
    }

    /// Optimal and falloff in one row when there is a falloff, else the optimal alone as "range".
    private func addRange(to rows: inout RowBuilder) {
        guard let optimal = values.optimal else { return }
        if let falloff = values.falloff {
            rows.add("Optimal + Falloff",
                     "\(FitStatFormat.distance(optimal)) + \(FitStatFormat.distance(falloff))")
        } else {
            rows.add("Range", FitStatFormat.distance(optimal))
        }
    }

    /// Collects the rows in the order they are added, keeping each one's id unique.
    private struct RowBuilder {
        var rows: [DigestRow] = []

        mutating func add(_ label: LocalizedStringKey, _ value: String) {
            rows.append(DigestRow(label: label, value: value, id: "\(rows.count)"))
        }
    }

    /// Which layer a repairer mends, and whose: a remote repairer's rate is not this fit's tank.
    private static func label(of repair: FitStats.Module.Repair) -> LocalizedStringKey {
        switch (repair.kind, repair.isRemote) {
        case (.shield, false): "Shield Repair"
        case (.armor, false): "Armor Repair"
        case (.hull, false): "Structure Repair"
        case (.shield, true): "Remote Shield Repair"
        case (.armor, true): "Remote Armor Repair"
        case (.hull, true): "Remote Structure Repair"
        }
    }

    // MARK: - The skill set

    /// The last segment of the caption: the label of `FitDocument.Skills.SetKind`.
    private var skillsLabel: String {
        FitPilotRoster(accounts: accounts, catalog: trainingContext?.catalog).label(of: skills)
    }
}

// The sheet with the snapshot and the digest written out by hand; complete on its first frame.
// Whether the figures are the engine's needs a live fit.
#Preview("Module") {
    FitItemSheetPreview(subject: .module(FitItemSheetPreview.moduleID))
}

#Preview("Rig") {
    FitItemSheetPreview(subject: .module(FitItemSheetPreview.rigID))
}

#Preview("Drone") {
    FitItemSheetPreview(subject: .drone(FitItemSheetPreview.droneID))
}

/// The sheet's own body, full frame, not inside a `.sheet`: a preview snapshots its first frame.
private struct FitItemSheetPreview: View {
    let subject: FitItemSubject

    private static let hullID = EntityID.hull(for: PilotID(0).rawValue)
    static let moduleID = ModuleID(rawValue: .module(0, in: .hi, on: hullID))
    static let rigID = ModuleID(rawValue: .module(0, in: .rig, on: hullID))
    static let droneID = DroneID(rawValue: .drone(0, on: hullID))

    /// Heavy Electron Blaster II with Antimatter Charge M, a Medium Hybrid Burst Aerator II and a
    /// stack of five Hammerhead II.
    private static let snapshot = FitSnapshot(
        pilotID: PilotID(0),
        shipTypeID: .vexor,
        modules: [
            FitSnapshot.Module(id: moduleID, typeID: .heavyElectronBlasterII, slot: .hi, socket: 0,
                               state: .active, effectiveState: .active, maxAllowedState: .overloaded,
                               charge: .antimatterChargeM, chargeGroups: [85], chargeSize: 2),
            FitSnapshot.Module(id: rigID, typeID: .mediumHybridBurstAeratorII, slot: .rig, socket: 0,
                               state: .offline, effectiveState: .offline, maxAllowedState: .offline,
                               charge: nil, chargeGroups: [], chargeSize: nil),
        ],
        drones: [FitSnapshot.Drone(id: droneID, typeID: .hammerheadII, count: 5, maxCount: 5, isActive: true, volume: 5, bandwidthUsed: 10)],
        resources: FitSnapshot.Resources(
            cpu: Resource(used: 420, total: 500),
            powerGrid: Resource(used: 9_000, total: 11_500),
            calibration: Resource(used: 200, total: 400),
            droneBay: Resource(used: 125, total: 125),
            droneBandwidth: Resource(used: 125, total: 125),
            dronesInSpace: SlotCapacity(used: 5, total: 5),
            slots: [:],
            turrets: SlotCapacity(used: 1, total: 4),
            launchers: SlotCapacity(used: 0, total: 0)
        ),
        stats: nil,
        warnings: []
    )

    private static let names: [TypeID: String] = [
        .heavyElectronBlasterII: "Heavy Electron Blaster II",
        .antimatterChargeM: "Antimatter Charge M",
        .mediumHybridBurstAeratorII: "Medium Hybrid Burst Aerator II",
        .hammerheadII: "Hammerhead II",
    ]

    var body: some View {
        FitItemSheet(
            subject: subject,
            snapshot: Self.snapshot,
            names: Self.names,
            skills: .all(5),
            digest: { subject in Self.digest(of: subject) },
            onSetState: { _, _ in },
            onSetDroneCount: { _, _ in },
            onSetDroneActive: { _, _ in },
            onRequestAmmo: { _ in },
            onShowAmmoInfo: { _ in },
            onApplyAmmoToAll: { _ in },
            onRemoveAmmo: { _ in },
            onRequestVariations: { _ in },
            onShowInfo: { _ in },
            onRemove: { _ in }
        )
        .environment(AccountStore())
    }

    /// Figures in the shape the engine answers in: a turret with everything, a rig with only what
    /// it costs, a drone stack with its damage split.
    private static func digest(of subject: FitItemSubject) -> FitItemDigest {
        var digest = FitItemDigest()
        switch subject {
        case .module(Self.moduleID):
            digest.dps = DamageVector(em: 0, thermal: 35.6, kinetic: 35.7, explosive: 0)
            digest.volley = DamageVector(em: 0, thermal: 80.2, kinetic: 80.2, explosive: 0)
            digest.cycleTime = 2.25
            digest.optimal = 2_400
            digest.falloff = 3_750
            digest.accuracyScore = 57.6
            digest.capacitorUse = 0.65
            digest.reloadTime = 5
            digest.cpu = 26
            digest.powerGrid = 92
        case .module(Self.rigID):
            digest.calibration = 100
            digest.cpu = 30
        case .drone:
            digest.dps = DamageVector(em: 0, thermal: 54.6, kinetic: 0, explosive: 0)
            digest.volley = DamageVector(em: 0, thermal: 160, kinetic: 0, explosive: 0)
            digest.cycleTime = 3
            digest.optimal = 4_200
            digest.falloff = 3_000
            digest.maxVelocity = 2_016
            digest.volumePerDrone = 25
            digest.bandwidthPerDrone = 25
        default:
            break
        }
        return digest
    }
}

// MARK: - Names

extension Entity.Module.State {
    /// The state's name as the sheet's segment and caption write it: "Overheat", not "overloaded".
    var title: String {
        switch self {
        case .offline: String(localized: "Offline")
        case .online: String(localized: "Online")
        case .active: String(localized: "Active")
        case .overloaded: String(localized: "Overheat")
        }
    }

    /// Every state from `.offline` up to and including `ceiling`, a value on the `UInt8` ladder.
    static func ladder(upTo ceiling: Entity.Module.State) -> [Entity.Module.State] {
        (0...ceiling.rawValue).compactMap(Entity.Module.State.init(rawValue:))
    }
}
