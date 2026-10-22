import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// The sheet that picks an implant for one implant slot, or a booster for any.
///
/// One screen with two modes: the two lists differ only in the slot attribute and the way they
/// are cut into sections. The chrome is `ModulePickerView`'s (its own `NavigationStack` and
/// `SDESectionView`, the same `Cancel` button), since a sheet does not inherit `liteDatabase`.
///
/// The list is flat apart from its section headings: a slot holds 60 to 171 implants or 3 to 24
/// boosters. Search is the system `.searchable` over the same ids, flat and by relevance.
///
/// Nothing here knows about the fit. The caller says which slot and which type stands in it now
/// (`current`), and gets one `TypeID` back; whether that is an `add` or a replacement is the
/// caller's to decide. `slot: nil` means every slot of the kind.
struct SlotItemPickerView: View {
    enum Kind {
        case implant
        case booster
    }

    let kind: Kind
    /// The slot's number as the engine counts it (`implantness`/`boosterness`, 1-based). `nil`
    /// means every slot of the kind.
    let slot: UInt16?
    /// What stands in the slot now, checkmarked and tinted like the ammo picker's loaded charge.
    var current: TypeID?
    /// Called once, right before the sheet dismisses itself; a tap on `current` calls it too.
    var onSelect: (TypeID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            SDESectionView { database in
                SlotItemPickerBrowser(
                    sde: database,
                    kind: kind,
                    slot: slot,
                    current: current,
                    searchText: searchText,
                    onSelect: select
                )
            }
            .hudScreen()
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: Text("Item name"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func select(_ typeID: TypeID) {
        onSelect(typeID)
        dismiss()
    }

    /// `Slot 7` and `Booster Slot 2`. With no slot there is no number to name: an empty cell is
    /// `Add Booster`, a tap on a standing one is `Replace Booster`.
    private var title: String {
        switch (kind, slot) {
        case let (.implant, .some(slot)): String(localized: "Slot \(Int(slot))")
        case let (.booster, .some(slot)): String(localized: "Booster Slot \(Int(slot))")
        case (.implant, .none): current == nil ? String(localized: "Add Implant") : String(localized: "Replace Implant")
        case (.booster, .none): current == nil ? String(localized: "Add Booster") : String(localized: "Replace Booster")
        }
    }

    /// What the list is of, under a title that names a slot; omitted when the title already says
    /// it.
    private var subtitle: String {
        guard slot != nil else { return "" }
        return switch kind {
        case .implant: String(localized: "Implants")
        case .booster: String(localized: "Boosters")
        }
    }
}

// MARK: - Body

/// The root of the sheet: the slot's items under headings, or search results in their place.
///
/// The ids of the slot are read in `body` and handed down as plain values: the item queries
/// filter on `id IN (…)`, and a read is synchronous.
private struct SlotItemPickerBrowser: View {
    let sde: SDEDatabase
    let kind: SlotItemPickerView.Kind
    let current: TypeID?
    let searchText: String
    let onSelect: (TypeID) -> Void

    @LiteQuery private var ids: [ItemIDRow]

    init(sde: SDEDatabase, kind: SlotItemPickerView.Kind, slot: UInt16?, current: TypeID?, searchText: String,
         onSelect: @escaping (TypeID) -> Void) {
        self.sde = sde
        self.kind = kind
        self.current = current
        self.searchText = searchText
        self.onSelect = onSelect
        _ids = LiteQuery(FittingBrowser.slotItemIDs(
            kind: kind == .booster ? .booster : .implant,
            slot: slot,
            // A booster with no market group is an expired event dose (slot 1 gives 24 boosters
            // instead of 44); the three implants without one are real.
            marketableOnly: kind == .booster
        ))
    }

    var body: some View {
        let slotIDs = ids.map(\.id)
        if searchText.isEmpty {
            SlotItemSectionsView(
                query: FittingBrowser.slotItems(ids: slotIDs),
                kind: kind,
                current: current,
                onSelect: onSelect
            )
        } else {
            SlotItemSearchResultsView(
                query: sde.pattern(searchText).map { FittingBrowser.slotItems(ids: slotIDs, matching: $0) },
                searchText: searchText,
                current: current,
                onSelect: onSelect
            )
        }
    }
}

/// The browse list: the slot's items under a heading per section.
private struct SlotItemSectionsView: View {
    @LiteQuery private var items: [SlotItemRow]
    let kind: SlotItemPickerView.Kind
    let current: TypeID?
    let onSelect: (TypeID) -> Void

    init(query: SQLQuery<SlotItemRow>, kind: SlotItemPickerView.Kind, current: TypeID?,
         onSelect: @escaping (TypeID) -> Void) {
        _items = LiteQuery(query)
        self.kind = kind
        self.current = current
        self.onSelect = onSelect
    }

    var body: some View {
        SlotItemSectionList(sections: SlotItemSection.sections(of: items, kind: kind), current: current,
                            onSelect: onSelect)
    }
}

/// The sections as drawn, apart from the query that fills them, so a preview can show them without
/// the database.
private struct SlotItemSectionList: View {
    let sections: [SlotItemSection]
    let current: TypeID?
    let onSelect: (TypeID) -> Void

    var body: some View {
        HUDList {
            ForEach(sections) { section in
                // No count in the heading: a section of a flat list is not drilled into.
                HUDListSection(section.rows, row: { item in
                    SlotItemButton(row: item.listRow, current: current, onSelect: onSelect)
                }, header: {
                    HUDSectionHeader(section.title)
                })
            }
        }
    }
}

/// Search results, flat and by relevance, as in the other pickers.
private struct SlotItemSearchResultsView: View {
    @LiteQuery private var results: [TypeListRow]
    let searchText: String
    let current: TypeID?
    let onSelect: (TypeID) -> Void

    init(query: SQLQuery<TypeListRow>?, searchText: String, current: TypeID?,
         onSelect: @escaping (TypeID) -> Void) {
        _results = LiteQuery(query)
        self.searchText = searchText
        self.current = current
        self.onSelect = onSelect
    }

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            HUDList {
                HUDListSection(results, row: { item in
                    SlotItemButton(row: item, current: current, onSelect: onSelect)
                }, header: {
                    HUDSectionHeader(Text("Results · \(results.count)"))
                })
            }
        }
    }
}

/// One tappable row of either list.
private struct SlotItemButton: View {
    let row: TypeListRow
    let current: TypeID?
    let onSelect: (TypeID) -> Void

    var body: some View {
        Button {
            onSelect(row.id)
        } label: {
            PickerTypeRow(row: row, isCurrent: row.id == current)
        }
        .contextMenu {
            // A plain `TypeInfoView`: the item is not in the fit yet.
            NavigationLink("Info", value: DatabaseRoute.type(row.id))
        }
        .hudRowButton(PickerTypeRow.rowStyle(isCurrent: row.id == current))
    }
}

// MARK: - Sections

/// One heading of the browse list and the rows under it.
///
/// Sections follow the data: implants by inventory group, boosters by strength.
struct SlotItemSection: Identifiable {
    let id: Int
    let title: Text
    var rows: [SlotItemRow]

    /// `rows` as `FittingBrowser.slotItems(ids:)` returns them, ordered by group name and then item
    /// name, cut into sections for `kind`.
    static func sections(of rows: [SlotItemRow], kind: SlotItemPickerView.Kind) -> [SlotItemSection] {
        switch kind {
        case .implant: byGroup(rows)
        case .booster: byTier(rows)
        }
    }

    /// An implant's section is its inventory group, named as the group is named (`Cyber Missile`)
    /// and ordered as the rows arrive, by the group's ordinal. The rows of one group are adjacent.
    private static func byGroup(_ rows: [SlotItemRow]) -> [SlotItemSection] {
        var sections: [SlotItemSection] = []
        for row in rows {
            if let last = sections.last, last.id == Int(row.groupID.rawValue) {
                sections[sections.count - 1].rows.append(row)
            } else {
                sections.append(SlotItemSection(id: Int(row.groupID.rawValue),
                                                title: Text(verbatim: row.groupName),
                                                rows: [row]))
            }
        }
        return sections
    }

    /// A booster's section is its strength, `dogmaItems.metaLevel`: `metaGroupID` is `NULL` on 295
    /// of the 429 boosters. The rows keep their order inside a tier.
    private static func byTier(_ rows: [SlotItemRow]) -> [SlotItemSection] {
        let byTier = Dictionary(grouping: rows) { BoosterTier(metaLevel: $0.metaLevel) }
        return BoosterTier.allCases.compactMap { tier in
            byTier[tier].map { SlotItemSection(id: tier.rawValue, title: tier.title, rows: $0) }
        }
    }
}

/// `0 → SYNTH`, `3 → STANDARD`, `5 → IMPROVED`, `6 → STRONG`, anything else and `NULL` → `OTHER`,
/// in the order the sections are drawn.
private enum BoosterTier: Int, CaseIterable {
    case synth, standard, improved, strong, other

    init(metaLevel: Int?) {
        switch metaLevel {
        case 0: self = .synth
        case 3: self = .standard
        case 5: self = .improved
        case 6: self = .strong
        default: self = .other
        }
    }

    /// Upper-cased by the section header.
    var title: Text {
        switch self {
        case .synth: Text("Synth")
        case .standard: Text(String(localized: "booster.grade.standard", defaultValue: "Standard", comment: "Booster grade, a group header in the booster picker (plural)"))
        case .improved: Text(String(localized: "booster.grade.improved", defaultValue: "Improved", comment: "Booster grade, a group header in the booster picker (plural)"))
        case .strong: Text("Strong")
        case .other: Text("Other")
        }
    }
}

#Preview("Implants") {
    // Slot 7, with Zor's Custom Navigation Link in it.
    SlotItemPickerView(kind: .implant, slot: 7, current: TypeID(rawValue: 19500)) { _ in }
        .environment(SDEStore())
}

#Preview("Boosters") {
    // Every marketable booster, with a Standard Drop Booster standing in the fit.
    SlotItemPickerView(kind: .booster, slot: nil, current: TypeID(rawValue: 15466)) { _ in }
        .environment(SDEStore())
}

#Preview("List") {
    // The list without the database: the sections and the checkmark.
    func row(_ id: UInt32, _ name: String, group: UInt16 = 1, _ groupName: String, level: Int? = nil) -> SlotItemRow {
        SlotItemRow(id: TypeID(rawValue: id), name: name, groupID: GroupID(rawValue: group), groupName: groupName,
                    metaGroupID: nil, metaGroupName: nil, metaLevel: level,
                    metaColorRed: nil, metaColorGreen: nil, metaColorBlue: nil)
    }
    let rows = [
        row(19500, "Zor's Custom Navigation Link", group: 1, "Cyber Navigation"),
        row(10001, "Eifyr and Co. 'Rogue' Evasive Maneuvering EM-701", group: 1, "Cyber Navigation"),
        row(10002, "Inherent Implants 'Noble' Remote Armor Repair Systems RA-701", group: 2, "Cyber Armor"),
    ]
    return NavigationStack {
        SlotItemSectionList(sections: SlotItemSection.sections(of: rows, kind: .implant),
                            current: TypeID(rawValue: 19500)) { _ in }
            .hudScreen()
            .navigationTitle("Slot 7")
            .navigationBarTitleDisplayMode(.inline)
    }
}
