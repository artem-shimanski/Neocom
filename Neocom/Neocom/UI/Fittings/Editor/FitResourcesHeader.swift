import DogmaKit
import SwiftUI

/// The editor's header panel: the hull and the skill set the fit is calculated for, then what the
/// fit spends against what the hull provides: six bars in a grid, CPU to drones in space.
///
/// Every number is the engine's own `Resource`, only drawn. A figure and its bar go `hudDanger`
/// exactly when `Resource.isOverloaded` says so; the panel's border does not change, since a fit
/// may be over budget. All six bars are always there, the zero ones too, so the rows do not
/// change with the hull. The `DPS · EHP · Cap` strip closes the panel and leads to the stats
/// screen.
struct FitResourcesHeader: View {
    let shipTypeID: TypeID
    /// Empty until the editor's name lookup has answered; the heading is blank meanwhile.
    let shipName: String
    /// The hull's race and group, for the line under its name; `nil` until the SDE read has
    /// answered.
    let shipContext: ShipContextRow?
    /// The set the fit is calculated for, for the chip.
    let skills: FitDocument.Skills
    /// How many implants and boosters the fit's pilot carries, for the second chip; counts only.
    let implantCount: Int
    let boosterCount: Int
    /// The system effect in force, short (`C4 Pulsar`), for the third chip; `nil` with none.
    var environmentLabel: String?
    let resources: FitSnapshot.Resources
    /// `nil` when the fit has no hull to evaluate; the strip is then left out, since zeros would
    /// read as a fit that does nothing.
    let stats: FitStatsSummary?
    /// The damage the strip's EHP is read against: the editor's pattern, so the header and the
    /// stats screen print the same figure.
    var damagePattern: DamageVector = FitDamagePattern.uniform.vector
    /// What the other ships of the fleet aim at this one, already in words. Empty for a fleet of
    /// one or when nothing is aimed here; the block is then not drawn.
    var incoming: [FleetEffectLine] = []
    /// Opens the skills screen, as the toolbar's Skills button does.
    let onShowSkills: () -> Void
    /// Opens the implants and boosters screen; the chip is its only entry point.
    let onShowImplants: () -> Void
    /// Opens the environment screen; the third chip is its only entry point.
    var onShowEnvironment: () -> Void = {}
    /// Opens the stats screen, as the toolbar's Stats button does.
    let onShowStats: () -> Void
    /// Opens the hull's info screen with the fit's figures in it.
    let onShowShipInfo: () -> Void

    @Environment(\.trainingContext) private var trainingContext
    @Environment(AccountStore.self) private var accounts

    var body: some View {
        HUDPanel {
            HStack(spacing: 14) {
                // The render and the name lead to the hull's info screen; the chips beside them are
                // buttons of their own.
                Button(action: onShowShipInfo) {
                    shipRender
                }
                .buttonStyle(.hudTile)
                .contextMenu { shipMenu }
                .accessibilityLabel(Text(verbatim: shipName))
                .accessibilityHint("Shows the hull's attributes in this fit")
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: onShowShipInfo) {
                        Text(verbatim: shipName)
                            .font(.hudCardTitle)
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.hudTile)
                    .contextMenu { shipMenu }
                    .accessibilityHidden(true)
                    if let hullLine {
                        Text(verbatim: hullLine)
                            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                            .lineLimit(1)
                    }
                    chips
                }
                Spacer(minLength: 0)
            }
            // 16 in from the top and the sides, 14 above the bars.
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Grid(horizontalSpacing: 14, verticalSpacing: 12) {
                ForEach(0..<(bars.count + 1) / 2, id: \.self) { row in
                    GridRow {
                        ForEach(bars[row * 2..<min(row * 2 + 2, bars.count)]) { bar in
                            HUDResourceCell(title: Text(bar.title), used: bar.used, total: bar.total,
                                            unit: bar.unit, isOverloaded: bar.isOverloaded)
                        }
                    }
                }
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.top, 4)
            .padding(.bottom, HUDMetrics.gutter)

            if let stats {
                HUDPanelRule()
                Button(action: onShowStats) {
                    HUDStatStrip(items: summaryItems(stats), showsChevron: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hudRow)
                .accessibilityHint("Shows the full stats")
            }

            if !incoming.isEmpty {
                HUDPanelRule()
                incomingBlock
            }
        }
    }

    /// `INCOMING FROM FLEET`, then one line per module or stack aimed here: whose it is, what it
    /// is, and what it gives.
    private var incomingBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Incoming from Fleet")
                .font(.hudMicro)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .accessibilityAddTraits(.isHeader)
            ForEach(incoming) { line in
                HUDEffectLine(source: Text(verbatim: line.source),
                              detail: Text(verbatim: line.detail),
                              amount: line.amount.map { Text(verbatim: $0) },
                              tone: line.tone)
            }
        }
        .padding(.horizontal, HUDMetrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    /// The three ways out of the header: the skill set, the pilot's implants and boosters, and the
    /// system effect. They wrap onto as many lines as they need on a narrow screen.
    private var chips: some View {
        HUDWrapLayout(spacing: 6) {
            HUDLinkChip(title: Text("Skills · \(skillsLabel)"), action: onShowSkills)
                .accessibilityLabel("Skills: \(skillsLabel)")
                .accessibilityHint("Changes the skills the fit is calculated with")
            HUDLinkChip(title: Text("Implants \(implantCount) · Boosters \(boosterCount)"),
                        action: onShowImplants)
                .accessibilityLabel("\(implantCount) implants, \(boosterCount) boosters")
                .accessibilityHint("Changes the implants and boosters of the fit's pilot")
            environmentChip
        }
    }

    /// `ENVIRONMENT · C4 PULSAR`, or `ENVIRONMENT` with nothing in force.
    @ViewBuilder
    private var environmentChip: some View {
        if let environmentLabel, !environmentLabel.isEmpty {
            HUDLinkChip(title: Text("Environment · \(environmentLabel)"), action: onShowEnvironment)
                .accessibilityLabel("Environment: \(environmentLabel)")
                .accessibilityHint("Changes the system effect the fit is calculated under")
        } else {
            HUDLinkChip(title: Text("Environment"), action: onShowEnvironment)
                .accessibilityHint("Changes the system effect the fit is calculated under")
        }
    }

    /// `GALLENTE · CRUISER`: race and group, whichever of them the SDE has.
    private var hullLine: String? {
        let parts = [shipContext?.raceName, shipContext?.groupName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The set in words, by `FitDocument.Skills.SetKind`.
    private var skillsLabel: String {
        FitPilotRoster(accounts: accounts, catalog: trainingContext?.catalog).label(of: skills)
    }

    /// DPS, effective HP and the capacitor. A stable capacitor reads as the level it settles at, an
    /// unstable one as how long it lasts. It takes `ok` when stable and `warn` when not, never
    /// `danger`: an unstable capacitor is not a broken fit.
    private func summaryItems(_ stats: FitStatsSummary) -> [HUDStatStrip.Item] {
        let capacitor = stats.capacitor
        let hitPoints = FitStatFormat.hpCompact(stats.effectiveHitPoints(against: damagePattern).sum())
        // Called in a closure: the app is main-actor by default, and passing a main-actor method to
        // a nonisolated generic like `Optional.map` loses that isolation (an error in Swift 6
        // mode).
        let capValue = capacitor.stableLevel.map { FitStatFormat.percent($0) }
            ?? FitStatFormat.clock(capacitor.lastsFor)
        return [
            HUDStatStrip.Item(id: 0, label: Text("DPS"),
                              value: Text(verbatim: FitStatFormat.dpsFigure(stats.damage.dps.sum()))),
            HUDStatStrip.Item(id: 1, label: Text("EHP"),
                              value: Text(verbatim: hitPoints.figure),
                              unit: hitPoints.unit.isEmpty ? nil : Text(verbatim: hitPoints.unit)),
            HUDStatStrip.Item(id: 2, label: Text("Cap"),
                              value: Text(verbatim: capValue),
                              color: capacitor.isStable ? .hudOk : .hudWarn,
                              unit: capacitor.isStable ? Text("Stable") : Text("Lasts")),
        ]
    }

    /// The six bars in a fixed order, two to a row. Always six.
    private var bars: [ResourceBar] {
        [
            ResourceBar(id: 0, title: "CPU", resource: resources.cpu),
            ResourceBar(id: 1, title: "PowerGrid", resource: resources.powerGrid),
            ResourceBar(id: 2, title: "Calibration", resource: resources.calibration),
            ResourceBar(id: 3, title: "Drone Bay", resource: resources.droneBay, unit: " m³"),
            ResourceBar(id: 4, title: "Bandwidth", resource: resources.droneBandwidth),
            ResourceBar(id: 5, title: "In Space", capacity: resources.dronesInSpace),
        ]
    }

    /// The hull's long-press menu, worded as a module row's.
    @ViewBuilder
    private var shipMenu: some View {
        Button(action: onShowShipInfo) {
            Label("Info", systemImage: "info.circle")
        }
        HUDCopyButton("Copy Name", value: shipName)
    }

    /// The hull's render, small, falling back to its plain icon when the server has no render; the
    /// plate's own `fallbackURL` does it, so the render is requested once.
    private var shipRender: some View {
        HUDImagePlate(url: EVEImage.render(typeID: Int64(shipTypeID.rawValue)),
                      size: 72,
                      fallbackURL: EVEImage.icon(typeID: Int64(shipTypeID.rawValue), size: 128))
    }
}

/// One bar of the header: its name, how much of it the fit spends, and whether that is over what
/// the hull gives.
private struct ResourceBar: Identifiable {
    var id: Int
    var title: LocalizedStringKey
    var used: Double
    var total: Double
    var isOverloaded: Bool
    /// Printed after the pair (`125/125 m³`), on the volume only.
    var unit: String?

    init(id: Int, title: LocalizedStringKey, resource: Resource, unit: String? = nil) {
        self.init(id: id, title: title, used: resource.used, total: resource.total,
                  isOverloaded: resource.isOverloaded, unit: unit)
    }

    /// Drones in space are a count against a ceiling, not an engine `Resource`.
    init(id: Int, title: LocalizedStringKey, capacity: SlotCapacity) {
        self.init(id: id, title: title, used: Double(capacity.used), total: Double(capacity.total),
                  isOverloaded: capacity.isOverloaded, unit: nil)
    }

    private init(id: Int, title: LocalizedStringKey, used: Double, total: Double,
                 isOverloaded: Bool, unit: String?) {
        self.id = id
        self.title = title
        self.used = used
        self.total = total
        self.isOverloaded = isOverloaded
        self.unit = unit
    }
}

extension Double {
    /// A resource amount as the editor prints it, with at most one decimal; shared by the header
    /// bars, the drone bay's free volume and the stats screen's rows.
    var resourceFigure: String {
        formatted(.number.precision(.fractionLength(0...1)))
    }
}

#Preview("Over budget") {
    FitResourcesHeaderPreview(
        resources: FitSnapshot.Resources(
            cpu: Resource(used: 420, total: 500),
            powerGrid: Resource(used: 12_000, total: 11_500),
            calibration: Resource(used: 200, total: 400),
            droneBay: Resource(used: 25, total: 125),
            droneBandwidth: Resource(used: 0, total: 125),
            dronesInSpace: SlotCapacity(used: 6, total: 5),
            slots: [:],
            turrets: SlotCapacity(used: 0, total: 4),
            launchers: SlotCapacity(used: 0, total: 0)
        )
    )
}

/// A hull with nothing to say about drones: both bars are still there, at 0/0.
#Preview("No drone bay") {
    FitResourcesHeaderPreview(
        resources: FitSnapshot.Resources(
            cpu: Resource(used: 287.5, total: 850),
            powerGrid: Resource(used: 0, total: 850),
            calibration: Resource(used: 0, total: 400),
            droneBay: Resource(used: 0, total: 0),
            droneBandwidth: Resource(used: 0, total: 0),
            dronesInSpace: SlotCapacity(used: 0, total: 5),
            slots: [:],
            turrets: SlotCapacity(used: 0, total: 0),
            launchers: SlotCapacity(used: 0, total: 0)
        )
    )
}

private struct FitResourcesHeaderPreview: View {
    let resources: FitSnapshot.Resources

    var body: some View {
        HUDList {
            Section {
                FitResourcesHeader(
                    // 17740 is the Vindicator.
                    shipTypeID: 17740,
                    shipName: "Vindicator",
                    shipContext: ShipContextRow(id: 17740, groupID: 27, rigSize: 3, categoryID: CategoryID.ship,
                                                groupName: "Battleship", raceName: "Gallente"),
                    skills: .all(5),
                    implantCount: 6,
                    boosterCount: 1,
                    resources: resources,
                    stats: nil,
                    onShowSkills: {},
                    onShowImplants: {},
                    onShowStats: {},
                    onShowShipInfo: {}
                )
                .hudBareRow()
            }
        }
        .environment(AccountStore())
    }
}
