import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// The open fleet at a glance, pushed from the editor's `More` menu: totals, ships, and every
/// effect one ship aims at another.
///
/// A tap on a ship shows it in the editor; a swipe takes it out of the fleet, keeping its record
/// in My Fits and clearing the targets aimed at it. The last ship cannot be removed.
struct FleetOverviewView: View {
    let model: FittingEditorModel

    @Environment(FittingStore.self) private var fittings
    @Environment(\.dismiss) private var dismiss
    @State private var isAddShipSheetPresented = false

    var body: some View {
        FleetOverviewBody(
            members: model.members(named: fittings.fits + fittings.drafts),
            effects: model.effects,
            selectedPilot: model.selectedPilot,
            canAddShip: model.canAddShip,
            onSelect: { pilot in
                model.select(pilot)
                dismiss()
            },
            onRemove: { model.removeShip($0) },
            onAddShip: { isAddShipSheetPresented = true }
        )
        .navigationTitle("Fleet")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAddShipSheetPresented) {
            FleetShipPickerView(fleetFittingIDs: model.ships.map(\.fittingID)) { fittingIDs in
                for fittingID in fittingIDs {
                    model.addShip(fittingID: fittingID)
                }
            }
        }
    }
}

private struct FleetOverviewBody: View {
    let members: [FleetMember]
    let effects: [FitSnapshot.Incoming]
    let selectedPilot: PilotID?
    let canAddShip: Bool
    let onSelect: (PilotID) -> Void
    let onRemove: (PilotID) -> Void
    let onAddShip: () -> Void

    @LiteQuery private var typeNames: [TypeNameRow]

    init(members: [FleetMember], effects: [FitSnapshot.Incoming], selectedPilot: PilotID?,
         canAddShip: Bool, onSelect: @escaping (PilotID) -> Void,
         onRemove: @escaping (PilotID) -> Void, onAddShip: @escaping () -> Void) {
        self.members = members
        self.effects = effects
        self.selectedPilot = selectedPilot
        self.canAddShip = canAddShip
        self.onSelect = onSelect
        self.onRemove = onRemove
        self.onAddShip = onAddShip
        // Sorted: the query is `@LiteQuery`'s cache key and must be stable across rebuilds.
        let ids = Set(members.map(\.shipTypeID)).union(effects.map(\.typeID))
        _typeNames = LiteQuery(SDEBrowser.typeNames(of: ids.sorted { $0.rawValue < $1.rawValue }))
    }

    var body: some View {
        let names = Dictionary(typeNames.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let shipNames = Dictionary(members.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let lines = effects.map { FleetEffectLine($0, shipNames: shipNames, typeNames: names) }
        HUDList {
            Section {
                HUDPanel {
                    HUDStatStrip(items: totals, valueFont: HUDFont.mono(22, weight: .semibold, relativeTo: .title3),
                                 unitPlacement: .below)
                }
                .hudBareRow()
            }

            HUDListSection {
                ForEach(members) { member in
                    if members.count > 1 {
                        HUDSwipeRow(onRemove: { onRemove(member.id) }, inContextMenu: false, allowsFullSwipe: true) {
                            shipRow(member, hullName: names[member.shipTypeID])
                        }
                        .contextMenu { shipMenu(member, canRemove: true) }
                    } else {
                        shipRow(member, hullName: names[member.shipTypeID])
                            .contextMenu { shipMenu(member, canRemove: false) }
                    }
                }
                HUDAddRow(title: "Add Ship",
                          caption: String(localized: "\(members.count)/\(Fit.Pilots.maxCount)"),
                          action: onAddShip)
                    .disabled(!canAddShip)
            } header: {
                HUDSectionHeader(Text("Ships · \(members.count)"))
            }

            HUDListSection {
                if lines.isEmpty {
                    Text("No module or drone is aimed at another ship.")
                        .font(.hudBody)
                        .foregroundStyle(Color.hudInkMuted)
                        .hudRow()
                } else {
                    ForEach(lines) { line in
                        HUDFlowRow(source: Text(verbatim: line.source),
                                   target: Text(verbatim: line.target),
                                   detail: Text(verbatim: line.detail),
                                   amount: line.amount.map { Text(verbatim: $0) },
                                   tone: line.tone)
                    }
                }
            } header: {
                HUDSectionHeader(Text("Remote Effects · \(lines.count)"))
            } footer: {
                HUDFootnote("Remote effects are applied as if every ship were in range. Swipe a ship to take it out of the fleet: its fit stays in My Fits, and modules aimed at it lose their target.")
            }
        }
    }

    private var totals: [HUDStatStrip.Item] {
        let dps = members.reduce(0) { $0 + $1.stats.dps.sum() }
        let hitPoints = FitStatFormat.hpCompact(members.reduce(0) { $0 + $1.stats.uniformEffectiveHitPoints.sum() })
        let repairs = effects.compactMap { $0.isActive ? $0.repair : nil }
        let given = repairs.reduce(0) { $0 + $1.hpPerSecond }
        return [
            HUDStatStrip.Item(id: 0, label: Text("Fleet DPS"),
                              value: Text(verbatim: FitStatFormat.dpsFigure(dps)),
                              unit: Text("\(members.count) Ships")),
            HUDStatStrip.Item(id: 1, label: Text("Reps Given"),
                              value: Text(verbatim: FitStatFormat.plain(given)),
                              color: given > 0 ? .hudOk : .hudInk,
                              unit: Text("HP/s", comment: "Unit: hit points per second")),
            HUDStatStrip.Item(id: 2, label: Text("EHP"),
                              value: Text(verbatim: hitPoints.figure + hitPoints.unit),
                              unit: Text("Total")),
        ]
    }

    /// A ship row's context menu; the last ship has no remove.
    @ViewBuilder
    private func shipMenu(_ member: FleetMember, canRemove: Bool) -> some View {
        Button {
            onSelect(member.id)
        } label: {
            Label("Show in Editor", systemImage: "square.and.pencil")
        }
        HUDCopyButton("Copy Name", value: member.name)
        if canRemove {
            Button(role: .destructive) {
                onRemove(member.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func shipRow(_ member: FleetMember, hullName: String?) -> some View {
        let isSelected = member.id == selectedPilot
        return Button {
            onSelect(member.id)
        } label: {
            HStack(spacing: 12) {
                HUDItemIcon(typeID: member.shipTypeID, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(verbatim: member.name)
                            .font(HUDFont.display(16, weight: .bold, relativeTo: .headline))
                            .foregroundStyle(Color.hudInk)
                            .lineLimit(1)
                        if let hullName {
                            HUDMetaBadge(text: Text(verbatim: hullName), color: .hudAccent)
                        }
                    }
                    Text(verbatim: statsLine(member.stats))
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(Color.hudInkBodyMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                if isSelected {
                    HUDStatusChip(text: Text("Shown"), color: .hudAccent, mark: .dot)
                }
                HUDChevron()
            }
            .hudRow(Self.rowStyle)
        }
        .hudRowButton(Self.rowStyle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Shows this ship in the editor")
    }

    private static let rowStyle = HUDRowStyle(minHeight: 68, verticalPadding: 10)

    /// `487 DPS · 14.1K EHP · CAP 41%` — the editor header's three figures on one line.
    private func statsLine(_ stats: FleetSnapshot.Ship.Stats) -> String {
        let hitPoints = FitStatFormat.hpCompact(stats.uniformEffectiveHitPoints.sum())
        let capacitor = stats.capacitor
        let cap = capacitor.stableLevel.map { FitStatFormat.percent($0) } ?? FitStatFormat.clock(capacitor.lastsFor)
        let dps = FitStatFormat.dps(stats.dps.sum())
        return String(localized: "\(dps) · \(hitPoints.figure)\(hitPoints.unit) EHP · CAP \(cap)", comment: "Fleet row stats line: DPS, effective HP, capacitor")
    }
}
