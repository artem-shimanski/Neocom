import DogmaKit
import SwiftData
import SwiftUI

/// Navigation token for the stats screen. A one-case value because `navigationDestination(item:)`
/// keys the destination on a value; the toolbar button and the header's summary strip both set it.
enum FitStatsRoute: Hashable {
    case stats
}

/// The fit's full statistics: what it takes, repairs, deals, how its capacitor holds, how it
/// moves, locks, and what it spends.
///
/// Pushed by `navigationDestination(item:)` in `FittingEditorView`. Nothing is computed here:
/// every number is a field of `FitStatsSummary` or `FitSnapshot.Resources`, read by the session
/// when the snapshot was built. Holding `model` rather than a snapshot keeps the screen current.
struct FitStatsView: View {
    let model: FittingEditorModel
    /// The fit's name, for the subtitle of the "Damage from…" list.
    let fitName: String

    /// CCP's average prices for the cost section, owned by `MarketSheet` (disk cache, an hour's
    /// TTL). The screen asks for freshness once and reads the table it has; an edit never fetches.
    @Environment(MarketSheet.self) private var market

    var body: some View {
        Group {
            if let snapshot = model.snapshot, let stats = snapshot.stats {
                FitStatsBody(resources: snapshot.resources, stats: stats, cost: cost(of: snapshot),
                             tacticalMode: tacticalMode(of: snapshot),
                             pattern: Bindable(model).damagePattern,
                             patternSources: FitDamageSources(snapshot: snapshot, allowed: model.allowedTypeIDs,
                                                              fitName: fitName))
            } else {
                // Only the moment between two snapshots: the editor does not offer this screen
                // without one.
                ContentUnavailableView {
                    Label("No Stats", systemImage: "chart.bar")
                } description: {
                    Text("This fit has no hull to calculate statistics for.")
                }
                .hudScreen()
            }
        }
        .task { await market.ensurePricesFresh() }
    }

    /// The mode's short name (`Sharpshooter`) for the resources' line, `nil` without a mode.
    private func tacticalMode(of snapshot: FitSnapshot) -> String? {
        guard let module = snapshot.modules.first(where: { $0.slot == .mode }) else { return nil }
        return model.tacticalModes.first { $0.id == module.typeID }?.title
    }

    /// The fit's worth at the prices in hand, or why there is none yet.
    private func cost(of snapshot: FitSnapshot) -> FitCostState {
        if market.prices.value != nil {
            return .ready(FitCost(snapshot) { market.ccpAverage(of: $0) })
        }
        if case .failed = market.prices.state { return .failed }
        return .loading
    }
}

/// The cost section's input: the sum, or the state of the price table that keeps it away.
private enum FitCostState {
    case loading
    case failed
    case ready(FitCost)
}

// MARK: - Body

private struct FitStatsBody: View {
    let resources: FitSnapshot.Resources
    let stats: FitStatsSummary
    let cost: FitCostState
    let tacticalMode: String?
    /// The damage the effective figures are read against: the editor's (`FittingEditorModel`), so
    /// it outlives this screen.
    @Binding var pattern: FitDamagePattern
    /// What the pattern sheet's "From ammo or drone…" list offers, as plain values.
    let patternSources: FitDamageSources

    /// Raw hit points or effective ones, for the whole screen; effective to begin with.
    /// View state: neither the snapshot nor the document holds it.
    @State private var mode: HitPointsMode = .effective
    @State private var isPatternSheetPresented = false

    var body: some View {
        HUDList {
            summaryPanel
            if mode == .effective {
                patternSection
            }
            tankSection
            repairSection
            damageSection
            capacitorSection
            if let fuel = stats.fuel {
                FitFuelSection(fuel: fuel)
            }
            navigationSection
            targetingSection
            resourcesSection
            costSection
        }
        .sheet(isPresented: $isPatternSheetPresented) {
            FitDamagePatternView(pattern: $pattern, sources: patternSources)
        }
    }

    // MARK: Summary

    /// The three figures a player glances at. The middle cell holds the switch that sets the
    /// reading of the tank and repair sections below.
    private var summaryPanel: some View {
        let damage = stats.damage
        let capacitor = stats.capacitor
        let hitPoints = FitStatFormat.hpCompact(hitPointsTotal)
        // Called in a closure: passing a main-actor method to a nonisolated generic loses its
        // isolation.
        let capValue = capacitor.stableLevel.map { FitStatFormat.percent($0) }
            ?? FitStatFormat.clock(capacitor.lastsFor)
        return HUDListSection {
            HUDStatStrip(
                items: [
                    HUDStatStrip.Item(
                        id: 0, label: Text("DPS"),
                        value: Text(verbatim: FitStatFormat.dpsFigure(damage.dps.sum())),
                        // Volley sits with DPS: the same fact over a different span of time.
                        unit: Text("Volley \(FitStatFormat.plain(damage.volley.sum(), fraction: 0...0))")),
                    HUDStatStrip.Item(
                        id: 1, label: Text(verbatim: mode.unit),
                        // `47.4K` whole; the line under the figure says which reading it is.
                        value: Text(verbatim: hitPoints.figure + hitPoints.unit),
                        unit: mode == .raw ? Text("Raw") : pattern.title,
                        control: AnyView(
                            HUDSegmentedSwitch(
                                options: [.init(value: HitPointsMode.raw, title: HitPointsMode.raw.unit),
                                          .init(value: HitPointsMode.effective, title: HitPointsMode.effective.unit)],
                                selection: $mode, label: "Hit Points")
                                .accessibilityHint("Shows hit points and repair rates raw or effective"))),
                    HUDStatStrip.Item(
                        id: 2, label: Text("Cap"),
                        value: Text(verbatim: capValue),
                        // `warn`, not `danger`: an unstable capacitor is not a fault.
                        color: capacitor.isStable ? .hudOk : .hudWarn,
                        unit: capacitor.isStable ? Text("Stable") : Text("Lasts")),
                ],
                valueFont: HUDFont.mono(22, weight: .semibold, relativeTo: .title2),
                // The units are figures and words of their own (`VOLLEY 1 214`); beside a 22 pt
                // value they would not fit.
                unitPlacement: .below)
            .hudRow(Self.edgeToEdge)
        }
    }

    /// The total of the reading showing: the summary's middle cell and the tank heading.
    private var hitPointsTotal: Double {
        shownHitPoints.sum()
    }

    /// Raw hit points, or the effective ones against the chosen pattern.
    private var shownHitPoints: HitPoints {
        mode == .raw ? stats.hitPoints : stats.effectiveHitPoints(against: pattern.vector)
    }

    // MARK: Tank

    /// One matrix: the four damage types across the top, a layer per row with its resistances and
    /// hit points, and the total in the heading.
    private var tankSection: some View {
        HUDListSection {
            HUDDefenseMatrix(layers: tankLayers, hitPointsColumn: Text(verbatim: mode.unit))
                .hudRow(Self.edgeToEdge)
        } header: {
            HUDSectionHeader(Text("Tank")) {
                Text(verbatim: "\(mode.unit) \(FitStatFormat.plain(hitPointsTotal, fraction: 0...0))")
            }
        }
    }

    // MARK: Damage pattern

    /// The damage the effective figures are read against, above the tank and only in the effective
    /// reading. The card is one button: the pattern's name (`APPROX` after an NPC faction's) and
    /// its shares in the matrix's columns.
    private var patternSection: some View {
        HUDListSection {
            Button {
                isPatternSheetPresented = true
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        pattern.title
                            .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInk)
                            .lineLimit(1)
                        if pattern.isApproximate {
                            HUDOutlineTag(text: Text("Approx", comment: "Badge after an NPC faction's damage pattern: its figures are approximate"),
                                          color: .hudInkMuted)
                        }
                        Spacer(minLength: 8)
                        HUDChevron()
                    }
                    HUDDamageBlock(pattern.vector, scale: .sum, numbers: .percent)
                        .accessibilityHidden(true)
                }
                .hudRow(Self.patternRowStyle)
            }
            .hudRowButton(Self.patternRowStyle)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Chooses the damage the effective hit points are calculated against")
        } header: {
            HUDSectionHeader(Text("Damage Pattern"))
        }
    }

    private static let patternRowStyle = HUDRowStyle(minHeight: 0, verticalPadding: 12)

    /// A card row for a block that pads itself — the stat strip, the defense matrix.
    private static let edgeToEdge = HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 0)

    private var tankLayers: [HUDDefenseMatrix.Layer] {
        let hitPoints = shownHitPoints
        let resistances = stats.resistances
        // "Structure", as the game's fitting window and the database screen's matrix call it;
        // `hull` is the engine's name.
        return [
            layer(0, "Shield", hitPoints.shield, resistances.shield),
            layer(1, "Armor", hitPoints.armor, resistances.armor),
            layer(2, "Structure", hitPoints.hull, resistances.hull),
        ]
    }

    private func layer(_ id: Int, _ title: LocalizedStringKey, _ hitPoints: Double,
                       _ resistances: DamageVector) -> HUDDefenseMatrix.Layer {
        HUDDefenseMatrix.Layer(
            id: id,
            title: Text(title),
            resistances: [resistances.em, resistances.thermal, resistances.kinetic, resistances.explosive],
            hitPoints: Text(verbatim: FitStatFormat.plain(hitPoints, fraction: 0...0)))
    }

    // MARK: Repair

    /// Every way the fit repairs itself, twice: with everything cycling, and as much of that as the
    /// capacitor keeps running. The total is set apart by a rule.
    private var repairSection: some View {
        let rows = repairRows
        return HUDListSection {
            HUDColumnsHeader(columns: [Text("Peak"), Text("Sustained")])
            ForEach(rows) { row in
                HUDColumnsRow(label: Text(row.title),
                              note: row.isMissing ? Text("No module fitted") : nil,
                              values: [figure(of: row.peak, isMissing: row.isMissing),
                                       figure(of: row.sustained, isMissing: row.isMissing)],
                              ink: row.isMissing ? .hudInkFaint : .hudInk,
                              divider: row.id == rows.first?.id ? .clear : .hudLineSubtle)
            }
            // Set apart by weight and a heavier rule; a rule of its own would be a row cut out of
            // the card.
            HUDColumnsRow(label: Text("Total"),
                          values: [figure(of: rows.reduce(0) { $0 + $1.peak }, isMissing: false),
                                   figure(of: rows.reduce(0) { $0 + $1.sustained }, isMissing: false)],
                          isEmphasized: true, divider: .hudLineLeader)
            // Inside the section: a footer would read as a note about the whole section.
            Text("Peak is with every repairer cycling; sustained is what the capacitor keeps running. Shield passive regen peaks at 25% shield.")
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .lineSpacing(3)
                .foregroundStyle(Color.hudInkMuted)
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 12))
        } header: {
            HUDSectionHeader(Text("Repair")) {
                Text(verbatim: mode.rateUnit)
            }
        }
    }

    /// The rates of the chosen reading. Passive shield regen is the same in both columns: the
    /// capacitor does not pay for it.
    private var repairRows: [RepairRow] {
        let tank = mode == .raw ? stats.tank : stats.effectiveTank(against: pattern.vector)
        let sustained = mode == .raw ? stats.sustainedTank : stats.effectiveSustainedTank(against: pattern.vector)
        return [
            RepairRow(id: 0, title: "Shield passive regen", peak: tank.passiveShield,
                      sustained: tank.passiveShield,
                      // A hull with no shield at all: the dash stands, a note would be wrong.
                      isMissing: false),
            RepairRow(id: 1, title: "Shield boost", peak: tank.shieldRepair,
                      sustained: sustained.shieldRepair, isMissing: tank.shieldRepair <= 0),
            RepairRow(id: 2, title: "Armor repair", peak: tank.armorRepair,
                      sustained: sustained.armorRepair, isMissing: tank.armorRepair <= 0),
            RepairRow(id: 3, title: "Structure repair", peak: tank.hullRepair,
                      sustained: sustained.hullRepair, isMissing: tank.hullRepair <= 0),
        ]
    }

    /// A rate without its unit, or a dash where the fit has nothing of that kind. A repairer whose
    /// sustained rate is zero prints `0.0`: the capacitor sustains none of it.
    private func figure(of value: Double, isMissing: Bool) -> Text {
        isMissing ? Text(verbatim: "—") : Text(verbatim: FitStatFormat.plain(value))
    }

    // MARK: Damage

    /// The total, the four types, and a row per source with its share by type under it.
    private var damageSection: some View {
        let damage = stats.damage
        return HUDListSection {
            HUDReadoutRow(Text("Total")) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: FitStatFormat.dpsFigure(damage.dps.sum()))
                        .font(HUDFont.mono(20, weight: .semibold, relativeTo: .title3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("DPS")
                        .font(.hudMicro)
                        .foregroundStyle(Color.hudInkMuted)
                }
            }
            // The block swaps on a tap between quantity per type and each type's share.
            HUDDamageBlock(damage.dps, scale: .sum, numbers: .raw, isToggleable: true)
                .hudRow(HUDRowStyle(divider: .clear, minHeight: 0, verticalPadding: 10))
            // Only sources that deal damage, so the lines add up to the total; fighters included.
            ForEach(damageSources) { source in
                VStack(alignment: .leading, spacing: 0) {
                    HUDReadoutRow(source.title, value: FitStatFormat.dps(source.vector.sum()))
                    HUDDamageSplitBar(vector: source.vector)
                        .padding(.horizontal, HUDMetrics.gutter)
                        .padding(.bottom, 12)
                }
                .accessibilityElement(children: .combine)
                // The card row is the pair, not the readout inside it: a list reads a cell off the
                // outermost view.
                .hudRow(Self.edgeToEdge)
            }
        } header: {
            HUDSectionHeader(Text("Damage"))
        } footer: {
            HUDFootnote("Tap the damage types to switch between damage per second and each type's share.")
        }
    }

    /// Where the damage comes from, with how many of that thing are firing.
    ///
    /// The count is the hull's hardpoint and drone figures: `turrets.used` is the number of
    /// turrets, drones deal damage only in space. Fighters and odd modules (a smartbomb) go without
    /// a count.
    private var damageSources: [DamageSource] {
        let damage = stats.damage
        return [
            DamageSource(id: 0, title: Text("Turrets · \(resources.turrets.used)"), vector: damage.turrets),
            DamageSource(id: 1, title: Text("Launchers · \(resources.launchers.used)"), vector: damage.launchers),
            DamageSource(id: 2, title: Text("Drones · \(resources.dronesInSpace.used) in space"), vector: damage.drones),
            DamageSource(id: 3, title: Text("Fighters"), vector: damage.fighters),
            DamageSource(id: 4, title: Text("Other modules"), vector: damage.otherModules),
        ]
        .filter { $0.vector.sum() > 0 }
    }

    // MARK: Capacitor

    private var capacitorSection: some View {
        let capacitor = stats.capacitor
        // Both lines take the capacitor's own colour: stable is `ok`, unstable is `warn`.
        let ink: Color = capacitor.isStable ? .hudOk : .hudWarn
        return HUDListSection {
            HUDReadoutRow("Capacity", value: FitStatFormat.energy(capacitor.capacity))
            HUDReadoutRow("Recharge", value: FitStatFormat.seconds(capacitor.rechargeTime))
            HUDReadoutRow(Text("Delta")) {
                Text(verbatim: FitStatFormat.energyRate(capacitor.delta))
                    .foregroundStyle(ink)
            }
            // Stable and unstable are different facts: the level it settles at, or how long it
            // lasts.
            if let level = capacitor.stableLevel {
                HUDReadoutRow(Text("Stable at")) {
                    Text(verbatim: FitStatFormat.percent(level)).foregroundStyle(ink)
                }
            } else {
                HUDReadoutRow(Text("Lasts")) {
                    Text(verbatim: FitStatFormat.seconds(capacitor.lastsFor)).foregroundStyle(ink)
                }
            }
        } header: {
            HUDSectionHeader(Text("Capacitor"))
        }
    }

    // MARK: Navigation

    private var navigationSection: some View {
        let navigation = stats.navigation
        return HUDListSection {
            HUDReadoutRow("Max velocity", value: FitStatFormat.speed(navigation.maxVelocity))
            HUDReadoutRow("Align time",
                          value: navigation.alignTime > 0 ? FitStatFormat.seconds(navigation.alignTime) : "—")
            HUDReadoutRow("Signature radius", value: FitStatFormat.distance(navigation.signatureRadius))
            HUDReadoutRow("Mass", value: FitStatFormat.mass(navigation.mass))
            HUDReadoutRow("Warp speed", value: FitStatFormat.auPerSecond(navigation.warpSpeed))
            HUDReadoutRow("Warp range",
                          value: navigation.maxWarpDistance > 0 ? FitStatFormat.au(navigation.maxWarpDistance) : "—")
        } header: {
            HUDSectionHeader(Text("Navigation"))
        }
    }

    // MARK: Targeting

    private var targetingSection: some View {
        let targeting = stats.targeting
        return HUDListSection {
            HUDReadoutRow("Range", value: FitStatFormat.distance(targeting.maxTargetRange))
            HUDReadoutRow("Scan resolution", value: FitStatFormat.millimeters(targeting.scanResolution))
            HUDReadoutRow("Max targets",
                          value: FitStatFormat.plain(Double(targeting.maxLockedTargets), fraction: 0...0))
            // Strength and kind on one line; the hull has exactly one sensor.
            HUDReadoutRow("Sensor", value: sensorFigure)
        } header: {
            HUDSectionHeader(Text("Targeting"))
        }
    }

    private var sensorFigure: String {
        let strength = FitStatFormat.plain(stats.targeting.ecmResistance)
        guard let type = stats.targeting.sensorType else { return strength }
        return "\(strength) \(type.name.localizedUppercase)"
    }

    // MARK: Resources

    /// What the fit spends, at the end of the screen and without bars. No `danger` tone: over
    /// budget shows in the figure that is over it.
    private var resourcesSection: some View {
        HUDListSection {
            resourceRow("CPU", resources.cpu, unit: String(localized: "tf", comment: "Unit: teraflops (CPU)"))
            resourceRow("PowerGrid", resources.powerGrid, unit: String(localized: "MW", comment: "Unit: megawatts (powergrid)"))
            resourceRow("Calibration", resources.calibration, unit: nil)
            // All four drone figures, zeros too, so the rows do not change with the hull.
            resourceRow("Drone bay", resources.droneBay, unit: String(localized: "m³", comment: "Unit: cubic metres"))
            resourceRow("Bandwidth", resources.droneBandwidth, unit: String(localized: "Mbit/s", comment: "Unit: megabits per second (drone bandwidth)"))
            CapacityRow(title: "Drones in space", capacity: resources.dronesInSpace)
            // Fighters only on a hull that takes them; most hulls have no hangar or tubes.
            if resources.fighterTubes.total > 0 || resources.fighterTubes.used > 0 {
                resourceRow("Fighter hangar", resources.fighterHangar, unit: String(localized: "m³", comment: "Unit: cubic metres"))
                CapacityRow(title: "Fighter tubes", capacity: resources.fighterTubes)
            }
            // Every rack on one line in the editor's order (`displayOrder`), only the racks the
            // hull has.
            HUDReadoutRow(Text("Slots")) { slotsFigure }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Slots"))
                .accessibilityValue(Text(verbatim: slotsDescription))
            if let tacticalMode {
                HUDReadoutRow("Tactical mode", value: tacticalMode)
            }
            // Hardpoints at zero too: a turret on a hull with none reads `1 / 0`.
            CapacityRow(title: "Turret hardpoints", capacity: resources.turrets)
            CapacityRow(title: "Launcher hardpoints", capacity: resources.launchers)
            // Not a budget with a bar: the engine reports the hold, not what is in it.
            HUDReadoutRow("Cargo hold", value: FitStatFormat.m³(stats.cargoCapacity))
        } header: {
            HUDSectionHeader(Text("Resources"))
        }
    }

    // MARK: Cost

    /// What the fit would cost at CCP's average prices: the total, then a line per kind of item.
    /// Presented as an estimate.
    private var costSection: some View {
        HUDListSection {
            HUDReadoutRow(Text(isPartialCost ? "Total (partial)" : "Total")) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: costTotal.map { ISK.compact($0) } ?? "—")
                        .font(HUDFont.mono(20, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(isPartialCost ? Color.hudWarn : Color.hudInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(verbatim: "ISK")
                        .font(.hudMicro)
                        .foregroundStyle(Color.hudInkMuted)
                }
            }
            if case let .ready(cost) = cost {
                ForEach(cost.lines) { line in
                    HUDReadoutRow(Text("\(line.group.title) · \(line.quantity)"),
                                  value: ISK.compact(line.value))
                }
            }
        } header: {
            HUDSectionHeader(Text("Cost"))
        } footer: {
            HUDFootnote(costFootnote)
        }
    }

    private var costTotal: Double? {
        if case let .ready(cost) = cost { cost.total } else { nil }
    }

    private var isPartialCost: Bool {
        if case let .ready(cost) = cost { cost.isPartial } else { false }
    }

    private var costFootnote: Text {
        switch cost {
        case .loading:
            Text("Loading average market prices…")
        case .failed:
            Text("Average market prices could not be loaded.")
        case let .ready(cost) where cost.isPartial:
            Text("Est. ISK · Average market prices · \(cost.unpricedTypes) item types without a price are not counted.")
        case .ready:
            Text("Est. ISK · Average market prices")
        }
    }

    private func resourceRow(_ title: LocalizedStringKey, _ resource: Resource, unit: String?) -> some View {
        let figure = "\(resource.used.resourceFigure) / \(resource.total.resourceFigure)"
        return HUDReadoutRow(Text(title)) {
            Text(verbatim: unit.map { "\(figure) \($0)" } ?? figure)
                .foregroundStyle(resource.isOverloaded ? Color.hudDanger : Color.hudInk)
        }
    }

    /// `3/4 · 4/4 · 5/5 · 3/3` — a pair per rack, each red on its own when that rack holds more
    /// than the hull gives.
    @ViewBuilder
    private var slotsFigure: some View {
        let racks = rackCapacities
        if racks.isEmpty {
            Text(verbatim: "—")
        } else {
            // Spaced by the stack: a `Text` of its own loses the space on one side.
            HStack(spacing: 5) {
                ForEach(Array(racks.enumerated()), id: \.offset) { index, rack in
                    if index > 0 {
                        Text(verbatim: "·").foregroundStyle(Color.hudInkFaint)
                    }
                    Text(verbatim: "\(rack.capacity.used)/\(rack.capacity.total)")
                        .foregroundStyle(rack.capacity.isOverloaded ? Color.hudDanger : Color.hudInk)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    /// The same row in words for a screen reader; the line itself names no rack.
    private var slotsDescription: String {
        rackCapacities
            .map { "\($0.slot.captionName) \($0.capacity.used)/\($0.capacity.total)" }
            .joined(separator: ", ")
    }

    private var rackCapacities: [(slot: Entity.Module.Slot, capacity: SlotCapacity)] {
        Entity.Module.Slot.displayOrder.compactMap { slot in
            guard let capacity = resources.slots[slot], capacity.total > 0 || capacity.used > 0 else { return nil }
            return (slot, capacity)
        }
    }
}

// MARK: - Rows and values

/// Raw hit points or effective ones. One switch for the whole screen: the tank matrix and the
/// repair table are the same two facts in the same two readings.
private enum HitPointsMode: Hashable {
    case raw, effective

    /// `HP` / `EHP`: the game's own abbreviations, the same in every language.
    var unit: String {
        switch self {
        case .raw: "HP"
        case .effective: "EHP"
        }
    }

    var rateUnit: String { "\(unit)/s" }
}

/// One line of the repair table: a kind of repair, its peak rate and its sustained one.
private struct RepairRow: Identifiable {
    var id: Int
    var title: LocalizedStringKey
    var peak: Double
    var sustained: Double
    /// Nothing of this kind is fitted: a dash and a word rather than a rate of `0.0`.
    var isMissing: Bool
}

/// One source of damage: what it is called, how many of it there are, and its damage by type.
private struct DamageSource: Identifiable {
    var id: Int
    var title: Text
    var vector: DamageVector
}

/// A slot or hardpoint count, `used / total`, going `hudDanger` when there are more than the
/// hull gives.
private struct CapacityRow: View {
    let title: LocalizedStringKey
    let capacity: SlotCapacity

    var body: some View {
        HUDReadoutRow(Text(title)) {
            Text(verbatim: "\(capacity.used) / \(capacity.total)")
                .foregroundStyle(capacity.isOverloaded ? Color.hudDanger : Color.hudInk)
        }
    }
}

private extension FitCost.Group {
    var title: LocalizedStringResource {
        switch self {
        case .hull: "Hull"
        case .modules: "Modules"
        case .charges: "Charges"
        case .drones: "Drones"
        case .implants: "Implants"
        case .boosters: "Boosters"
        }
    }
}

private extension SensorType {
    /// The sensor's name as a string, printed after the strength in caps.
    var name: String {
        switch self {
        case .radar: String(localized: "Radar")
        case .ladar: String(localized: "Ladar")
        case .magnetometric: String(localized: "Magnetometric")
        case .gravimetric: String(localized: "Gravimetric")
        }
    }
}

// MARK: - Preview

/// Opens a real fit through the real session: the summary is made of engine values with no
/// public initialiser.
private struct FitStatsPreview: View {
    let fittingID: UUID

    @Environment(FittingStore.self) private var fittings
    @Environment(SDEStore.self) private var sde
    @State private var model: FittingEditorModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    SDESectionView { _ in FitStatsView(model: model, fitName: "Vexor") }
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            let model = FittingEditorModel(fittingID: fittingID, store: fittings, sde: sde)
            await model.load()
            self.model = model
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Fitting.self, configurations: .init(isStoredInMemoryOnly: true))
    let store = FittingStore(context: container.mainContext)
    let id = store.create(
        shipTypeID: 17740,
        name: "Vindicator",
        document: FitDocument(pilots: [.init(skills: .init(default: 5), ship: .init(type: 17740))])
    )
    return FitStatsPreview(fittingID: id)
        .environment(store)
        .environment(SDEStore())
        .environment(MarketSheet())
        // Nothing else holds the container, and a `ModelContext` does not keep it alive: reading
        // through a released one crashes inside SwiftData.
        .modelContainer(container)
}
