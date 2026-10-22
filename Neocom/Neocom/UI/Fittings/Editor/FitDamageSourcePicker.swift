import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// What the "Damage from…" list is built from, read off the snapshot when the pattern sheet
/// opens: the fit's items, the charge slots of its modules and the hull's allowed types.
struct FitDamageSources: Hashable {
    /// The charge groups and the size one module takes, as the ammo picker reads them.
    struct ChargeSlot: Hashable {
        var groups: [GroupID]
        var size: UInt8?

        func accepts(_ row: DamageItemRow) -> Bool {
            groups.contains(row.groupID) && (size == nil || row.chargeSize == size)
        }
    }

    var fitName: String
    /// The charges loaded in the fit's modules, then the drones in its bay, each once, in the fit's
    /// order.
    var inFit: [TypeID]
    var chargeSlots: [ChargeSlot]
    var allowed: [TypeID]

    init(fitName: String, inFit: [TypeID], chargeSlots: [ChargeSlot], allowed: [TypeID]) {
        self.fitName = fitName
        self.inFit = inFit
        self.chargeSlots = chargeSlots
        self.allowed = allowed
    }

    init(snapshot: FitSnapshot, allowed: [TypeID], fitName: String) {
        var seen = Set<TypeID>()
        let charges = snapshot.modules.compactMap(\.charge)
        let drones = snapshot.drones.filter { !$0.isFighter }.map(\.typeID)
        inFit = (charges + drones).filter { seen.insert($0).inserted }
        var slots: [ChargeSlot] = []
        for module in snapshot.modules where !module.chargeGroups.isEmpty {
            let slot = ChargeSlot(groups: module.chargeGroups, size: module.chargeSize)
            if !slots.contains(slot) { slots.append(slot) }
        }
        chargeSlots = slots
        self.allowed = allowed
        self.fitName = fitName
    }

    /// Every group any module of the fit takes charges from.
    var chargeGroups: [GroupID] {
        Array(Set(chargeSlots.flatMap(\.groups)))
    }
}

/// The third way to set the damage pattern: an ammo charge or a drone whose damage split becomes
/// the pattern; its amount does not matter.
///
/// Pushed inside the pattern sheet's stack, in three sections: what the fit carries, the charges
/// that fit its modules, and every combat drone the hull is not barred from. Items that deal no
/// damage (scripts, probes, mining and EWAR drones) are left out.
struct FitDamageSourcePicker: View {
    let sources: FitDamageSources
    @Binding var pattern: FitDamagePattern

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SDESectionView { _ in
            FitDamageSourceQueries(sources: sources, current: pattern.item?.typeID, onSelect: select)
        }
        .navigationTitle("Damage from…")
        .navigationSubtitle(sources.fitName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Sets the pattern and goes back to the sheet.
    private func select(_ row: DamageItemRow, damage: DamageVector) {
        if let picked = FitDamagePattern.item(.init(typeID: row.id, name: row.name), damage: damage) {
            pattern = picked
        }
        dismiss()
    }
}

// MARK: - Lists

/// The three item reads; the damage of their rows is the next view's read, on the ids these hand
/// down.
private struct FitDamageSourceQueries: View {
    let sources: FitDamageSources
    let current: TypeID?
    let onSelect: (DamageItemRow, DamageVector) -> Void

    @LiteQuery private var inFit: [DamageItemRow]
    @LiteQuery private var charges: [DamageItemRow]
    @LiteQuery private var drones: [DamageItemRow]

    init(sources: FitDamageSources, current: TypeID?, onSelect: @escaping (DamageItemRow, DamageVector) -> Void) {
        self.sources = sources
        self.current = current
        self.onSelect = onSelect
        _inFit = LiteQuery(FittingBrowser.damageItems(ids: sources.inFit))
        _charges = LiteQuery(FittingBrowser.damageCharges(inGroups: sources.chargeGroups))
        _drones = LiteQuery(FittingBrowser.damageDrones(allowed: sources.allowed))
    }

    var body: some View {
        let order = Dictionary(sources.inFit.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sections = [
            FitDamageSourceSection(id: 0, title: Text("In This Fit"),
                                   rows: inFit.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }),
            FitDamageSourceSection(id: 1, title: Text("Ammo"),
                                   rows: charges.filter { row in sources.chargeSlots.contains { $0.accepts(row) } }),
            // Light to heavy, by name within a size; the index keeps the sort stable.
            FitDamageSourceSection(id: 2, title: Text("Drones"),
                                   rows: drones.enumerated()
                                       .sorted { ($0.element.volume ?? .infinity, $0.offset) < ($1.element.volume ?? .infinity, $1.offset) }
                                       .map(\.element)),
        ].filter { !$0.rows.isEmpty }
        FitDamageSourceList(sections: sections, current: current, onSelect: onSelect)
    }
}

private struct FitDamageSourceSection: Identifiable {
    let id: Int
    let title: Text
    let rows: [DamageItemRow]
}

/// The sections as drawn, each row with its damage split.
private struct FitDamageSourceList: View {
    let sections: [FitDamageSourceSection]
    let current: TypeID?
    let onSelect: (DamageItemRow, DamageVector) -> Void

    @LiteQuery private var attributes: [TypeAttribute]

    init(sections: [FitDamageSourceSection], current: TypeID?, onSelect: @escaping (DamageItemRow, DamageVector) -> Void) {
        self.sections = sections
        self.current = current
        self.onSelect = onSelect
        _attributes = LiteQuery(FittingBrowser.damageAttributes(of: Array(Set(sections.flatMap { $0.rows.map(\.id) }))))
    }

    var body: some View {
        let damage = damageByType
        HUDList(isTransparent: true) {
            ForEach(sections) { section in
                HUDListSection(section.rows, row: { row in
                    let vector = damage[row.id] ?? DamageVector()
                    let isCurrent = row.id == current
                    Button {
                        onSelect(row, vector)
                    } label: {
                        PickerTypeRow(row: row.listRow, subtitle: HUDDamageType.splitLine(vector), isCurrent: isCurrent)
                    }
                    .contextMenu {
                        NavigationLink("Info", value: DatabaseRoute.type(row.id))
                    }
                    .hudRowButton(PickerTypeRow.rowStyle(isCurrent: isCurrent))
                }, header: {
                    HUDSectionHeader(section.title)
                })
            }
            Section {
                HUDFootnote("The item's damage split becomes the pattern; its amount does not matter.")
                    .hudBareRow()
            }
        }
    }

    /// Each type's four values; a value the SDE has no row for is zero.
    private var damageByType: [TypeID: DamageVector] {
        var result: [TypeID: DamageVector] = [:]
        for attribute in attributes {
            guard let index = FittingBrowser.damageAttributeIDs.firstIndex(of: attribute.attributeID) else { continue }
            result[attribute.typeID, default: DamageVector()][index] = attribute.value
        }
        return result
    }
}
