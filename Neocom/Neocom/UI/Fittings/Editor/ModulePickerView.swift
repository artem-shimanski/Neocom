import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// The "+ Add Module", "+ Add Drone" and "+ Add Fighter" sheets, the ammo picker and the
/// variations picker an item's sheet opens: one chrome (its own `NavigationStack` and
/// `SDESectionView`, the same `Cancel` button, as in `ShipPickerView`), three bodies.
///
/// The bodies do not share a query shape: a charge has no group level and no hull filter, and a
/// family needs its root resolved first, so `Content` picks the body. Modules, drones and
/// fighters are one body: the market tree, narrowed to what the hull takes.
struct ModulePickerView: View {
    /// What this sheet lists.
    enum Content {
        /// Browse `kind` down the market tree, or search across all of it: the "+ Add Module" rows.
        ///
        /// `slotName` and `hullName` are for the headings only, already worded: the picker queries
        /// the SDE for items, never for the fit it serves.
        case items(kind: DogmaItemKind, rigSize: UInt8?, structureHull: Bool, allowed: [TypeID], slotName: String, hullName: String)
        /// Browse the drones down the market tree, or search across them: the "+ Add Drone" row.
        /// Its own case: a drone has no slot or rig size, and the screen adds a budget panel.
        ///
        /// `bay` and `bandwidth` are what the fit has and spends when the sheet opens, shown above
        /// the list; nothing refuses a drone that does not fit them.
        case drones(allowed: [TypeID], hullName: String, bay: Resource, bandwidth: Resource)
        /// The fighters of one squadron type down the market tree: the "+ Add Fighter" row of that
        /// type's section. `hangar` and `slots` (the type's own) are what the fit has when the
        /// sheet opens. The editor offers the row only while a slot is free.
        case fighters(squadron: Entity.Drone.Squadron, allowed: [TypeID], hullName: String,
                      hangar: Resource, slots: SlotCapacity)
        /// A module's own charges by meta tier: `groups` and `size` from the module's `chargeGroups`
        /// and `chargeSize` in the snapshot.
        ///
        /// `loaded` is the charge already in the module, checkmarked. `moduleName` is the subtitle;
        /// with `sameTypeCount` (modules of this very type in the fit) it labels "Apply to All",
        /// which only exists past one.
        case charges(groups: [GroupID], size: UInt8?, loaded: TypeID?, moduleName: String, sameTypeCount: Int)
        /// A module's variation family: "Variations…" in its context menu. `kind` is the slot the
        /// module stands in, taken from the row. `rigSize`/`allowed` are the hull filters `.items`
        /// carries.
        case variations(kind: DogmaItemKind, typeID: TypeID, rigSize: UInt8?, structureHull: Bool, allowed: [TypeID])
    }

    let content: Content
    /// Called once, right before the sheet dismisses itself.
    var onSelect: (TypeID) -> Void
    /// The ammo picker's second way out: the pick goes to every module of the type. Called only
    /// once the "Apply to All" button has been armed.
    var onApplyToAll: ((TypeID) -> Void)?

    /// The market-tree sheets: told the market groups an item was picked from (the whole stack as
    /// pushed, root first) right before `onSelect`; empty for an item on the root screen. Picks
    /// from search results do not report one.
    var onSelectFromGroup: (([MarketGroupID]) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var appliesToAll = false
    /// The group stack. A market-tree sheet starts pushed into `initialGroups` when the editor
    /// remembers a market group for this slot.
    ///
    /// It holds the groups as tapped. A level with one sub-group and nothing of its own is never a
    /// screen (`MarketPickerLevel`), so the stack has no entry for a skipped level.
    @State private var path: [ModulePickerRoute]

    init(content: Content, initialGroups: [MarketGroupID] = [], onSelectFromGroup: (([MarketGroupID]) -> Void)? = nil,
         onSelect: @escaping (TypeID) -> Void, onApplyToAll: ((TypeID) -> Void)? = nil) {
        self.content = content
        self.onSelect = onSelect
        self.onApplyToAll = onApplyToAll
        self.onSelectFromGroup = onSelectFromGroup
        _path = State(initialValue: initialGroups.map(ModulePickerRoute.marketGroup))
    }

    var body: some View {
        NavigationStack(path: $path) {
            SDESectionView { database in
                switch content {
                case .items, .drones, .fighters:
                    if let pick = marketPick {
                        MarketPickerBrowser(sde: database, pick: pick, searchText: searchText,
                                            onSelectFromTree: { typeID in
                                                onSelectFromGroup?([])
                                                select(typeID)
                                            },
                                            onSelect: select)
                            .navigationDestination(for: ModulePickerRoute.self) { route in
                                // Reapplied: a pushed screen does not reliably see `liteDatabase`
                                // from where the destination was registered.
                                MarketPickerLevel(groupID: route.marketGroupID, pick: pick, isRoot: false) { typeID in
                                    // The stack as it stands leads to the screen the tap came from,
                                    // which is the top of it.
                                    onSelectFromGroup?(path.map(\.marketGroupID))
                                    select(typeID)
                                }
                                .liteDatabase(database.database)
                            }
                    }
                case let .charges(groups, size, loaded, moduleName, sameTypeCount):
                    ChargePickerBrowser(
                        sde: database,
                        groups: groups,
                        size: size,
                        loaded: loaded,
                        moduleName: moduleName,
                        sameTypeCount: onApplyToAll == nil ? 0 : sameTypeCount,
                        searchText: searchText,
                        appliesToAll: $appliesToAll,
                        onSelect: select
                    )
                case let .variations(kind, typeID, rigSize, structureHull, allowed):
                    ModulePickerVariationsView(
                        kind: kind,
                        typeID: typeID,
                        rigSize: rigSize,
                        structureHull: structureHull,
                        allowed: allowed,
                        onSelect: select
                    )
                }
            }
            .hudScreen()
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(if: hasSearch, text: $searchText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func select(_ typeID: TypeID) {
        if appliesToAll, let onApplyToAll {
            onApplyToAll(typeID)
        } else {
            onSelect(typeID)
        }
        dismiss()
    }

    /// The market-tree sheets' narrowing and dress; `nil` for the other two.
    private var marketPick: MarketPick? {
        switch content {
        case let .items(kind, rigSize, structureHull, allowed, slotName, hullName):
            MarketPick(kind: kind, allowed: allowed, rigSize: rigSize, structureHull: structureHull, squadron: nil,
                       levelName: slotName, hullName: hullName, budget: nil, figures: .cpuAndPower)
        case let .drones(allowed, hullName, bay, bandwidth):
            MarketPick(kind: .drone, allowed: allowed, rigSize: nil, structureHull: nil, squadron: nil,
                       levelName: Entity.Drone.Squadron.none.pluralTitle, hullName: hullName,
                       budget: .drones(bay: bay, bandwidth: bandwidth), figures: .drone)
        case let .fighters(squadron, allowed, hullName, hangar, slots):
            // `.none` has no membership attribute and would list every fighter of the kind.
            MarketPick(kind: squadron.itemKind, allowed: allowed, rigSize: nil, structureHull: nil,
                       squadron: squadron.membershipAttribute,
                       levelName: squadron.pluralTitle, hullName: hullName,
                       budget: .fighters(hangar: hangar, slots: slots), figures: .fighter)
        case .charges, .variations:
            nil
        }
    }

    /// Whether `.searchable` belongs on this presentation. Every list but a variation family has
    /// one: a module's charge list runs to dozens (58 for a medium hybrid gun).
    private var hasSearch: Bool {
        switch content {
        // A squadron type is two dozen fighters at most, and a family a handful of variants.
        case .variations, .fighters: false
        default: true
        }
    }

    private var title: String {
        switch content {
        case let .items(kind, _, _, _, _, _): Self.title(for: kind)
        case .drones: String(localized: "Add Drone")
        case .fighters: String(localized: "Add Fighter")
        case .charges: String(localized: "Ammo")
        case .variations: String(localized: "Variations")
        }
    }

    /// The line under the title: the module the ammunition is for.
    private var subtitle: String {
        switch content {
        case let .charges(_, _, _, moduleName, _): moduleName
        case let .drones(_, hullName, _, _): hullName
        case let .fighters(_, _, hullName, _, _): hullName
        case .items, .variations: ""
        }
    }

    private static func title(for kind: DogmaItemKind) -> String {
        switch kind {
        // The slot is not in the title: the root's section heading names it.
        case .hi, .med, .low: String(localized: "Add Module")
        case .rig, .structureRig: String(localized: "Add Rig")
        case .subsystem: String(localized: "Add Subsystem")
        case .service: String(localized: "Add Service Module")
        default: String(localized: "Add Item")
        }
    }
}

/// Where a group row of the picker leads: a market group of the item tree.
private enum ModulePickerRoute: Hashable {
    case marketGroup(MarketGroupID)

    var marketGroupID: MarketGroupID {
        switch self {
        case let .marketGroup(id): id
        }
    }
}

private extension View {
    /// `.searchable`, but only when `isEnabled`; see `ModulePickerView.hasSearch`.
    @ViewBuilder
    func searchable(if isEnabled: Bool, text: Binding<String>) -> some View {
        if isEnabled {
            self.searchable(text: text, prompt: Text("Item name"))
        } else {
            self
        }
    }
}

// MARK: - The market tree

/// What one market-tree sheet narrows the tree to, and how its screens are worded and dressed:
/// the module, drone and fighter pickers differ in nothing else.
private struct MarketPick {
    var kind: DogmaItemKind
    var allowed: [TypeID]
    var rigSize: UInt8?
    var structureHull: Bool?
    /// The fighter squadron type's membership attribute (`FittingBrowser.fittingMarketGroups`).
    var squadron: AttributeID?
    /// What is being picked for, already worded: "High slot", "Drones", "Light Fighters". The
    /// root's section heading and every pushed screen's subtitle.
    var levelName: String
    var hullName: String
    /// What the fit has left of what the item costs, over every list of the sheet.
    var budget: PickerBudget?
    /// The line under an item's name.
    var figures: Figures

    enum Figures {
        /// `26 tf · 92 MW`.
        case cpuAndPower
        /// `5 m³ · 5 Mbit/s each`.
        case drone
        /// `5 000 m³ each`.
        case fighter
    }

    func groups(inParent parent: MarketGroupID?) -> SQLQuery<MarketGroupListRow> {
        FittingBrowser.fittingMarketGroups(kind: kind, inParent: parent, allowed: allowed, rigSize: rigSize,
                                           structureHull: structureHull, squadron: squadron)
    }

    func items(inMarketGroup group: MarketGroupID) -> SQLQuery<TypeListRow> {
        FittingBrowser.fittingItems(kind: kind, inMarketGroup: group, allowed: allowed, rigSize: rigSize,
                                    structureHull: structureHull, squadron: squadron)
    }

    /// Search across the whole kind; the fighter sheet has no search field, so the squadron is not
    /// needed.
    func items(matching pattern: FTS5Pattern) -> SQLQuery<TypeListRow> {
        FittingBrowser.fittingItems(kind: kind, matching: pattern, allowed: allowed, rigSize: rigSize,
                                    structureHull: structureHull)
    }

    func subtitle(of row: TypeListRow) -> String? {
        switch figures {
        case .cpuAndPower:
            row.cpuAndPowerText
        case .drone:
            row.droneFiguresText
        case .fighter:
            row.volume.map {
                String(localized: "\($0.resourceFigure) m³ each", comment: "Fighter volume per fighter, number then unit")
            }
        }
    }

    /// The words under a list of items: what the list leaves out, or what adding does.
    var footnote: Text {
        switch budget {
        case nil:
            ModulePickerFootnote.items
        case .drones:
            // One block, one footnote.
            Text("\(DronePickerFootnote.added) \(DronePickerFootnote.overBudget)")
        case .fighters:
            Text("A fighter is added as a full squadron and takes one slot of its type. It is launched into space while a fighter tube is free, and stays in the hangar otherwise.")
        }
    }

    /// The footnote of search results: the drone one keeps only what the budget does not stop.
    var searchFootnote: Text {
        switch budget {
        case .drones: DronePickerFootnote.overBudget
        default: footnote
        }
    }
}

/// The root of a market-tree sheet: the tree narrowed to what fits, or search results in its
/// place.
private struct MarketPickerBrowser: View {
    let sde: SDEDatabase
    let pick: MarketPick
    let searchText: String
    /// A pick on the root screen itself.
    let onSelectFromTree: (TypeID) -> Void
    /// A pick from search results.
    let onSelect: (TypeID) -> Void

    var body: some View {
        if searchText.isEmpty {
            MarketPickerLevel(groupID: nil, pick: pick, isRoot: true, onSelect: onSelectFromTree)
        } else {
            MarketPickerSearchResultsView(query: sde.pattern(searchText).map { pick.items(matching: $0) },
                                          pick: pick, searchText: searchText, onSelect: onSelect)
        }
    }
}

/// One level of the tree (the roots when `groupID` is `nil`). The root, when it would be a screen
/// of a single row, shows the level under that row in its place, repeatedly; a level opened by a
/// tap is never collapsed, so only the leading chain of single rows is skipped. A rig slot opens
/// on the rig groups; a light-fighter slot on the light fighters themselves.
///
/// Collapsed here rather than in the stack: queries are synchronous, and the stack keeps the
/// groups as tapped (`ModulePickerView.path`). A collapsed root is still the root.
private struct MarketPickerLevel: View {
    @LiteQuery private var header: MarketGroupHeader?
    @LiteQuery private var groups: [MarketGroupListRow]
    @LiteQuery private var items: [TypeListRow]
    let pick: MarketPick
    let isRoot: Bool
    let onSelect: (TypeID) -> Void

    init(groupID: MarketGroupID?, pick: MarketPick, isRoot: Bool, onSelect: @escaping (TypeID) -> Void) {
        _header = LiteQuery(groupID.map { SDEBrowser.header(ofMarketGroup: $0) })
        _groups = LiteQuery(pick.groups(inParent: groupID))
        _items = LiteQuery(groupID.map { pick.items(inMarketGroup: $0) })
        self.pick = pick
        self.isRoot = isRoot
        self.onSelect = onSelect
    }

    var body: some View {
        if isRoot, items.isEmpty, groups.count == 1, let only = groups.first {
            // Type-erased: a view that contains itself has no concrete type to name.
            AnyView(MarketPickerLevel(groupID: only.id, pick: pick, isRoot: true, onSelect: onSelect))
        } else if isRoot {
            list
        } else {
            list
                .navigationTitle(header?.name ?? "")
                .navigationSubtitle(Text("\(pick.levelName) · \(pick.hullName)"))
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The sub-groups with something that fits in them, and the items filed on this group under a
    /// heading per meta tier, both at once.
    private var list: some View {
        HUDList {
            if let budget = pick.budget {
                PickerBudgetPanel(budget: budget)
            }
            if !groups.isEmpty {
                HUDListSection(groups, row: { group in
                    MarketGroupRowView(group: group, fallbackIconID: header?.iconID,
                                       value: ModulePickerRoute.marketGroup(group.id))
                }, header: {
                    // `HIGH SLOT · 1 GROUPS`: the section header upper-cases whatever it is given.
                    if isRoot {
                        HUDSectionHeader(Text("\(pick.levelName) · \(groups.count) groups"))
                    } else {
                        HUDSectionHeader(Text("Groups · \(groups.count)"))
                    }
                })
            }
            // The database screens' grouping with this sheet's row: the tier is in the heading and
            // the badge, and the line under the name is the figures the list is sorted by, so the
            // subtitle stays.
            TypeListSections(rows: items, order: .ascending, headsEverySection: true) { item, _ in
                MarketPickerRow(item: item, subtitle: pick.subtitle(of: item), onSelect: onSelect)
            }
            // A block under the last tier, not its footnote; absent on a branch of sub-groups
            // alone.
            if !items.isEmpty {
                Section {
                    HUDFootnote(pick.footnote)
                        .hudBareRow()
                }
            }
        }
    }
}

/// One item of a market-tree sheet: a tap picks it, a touch and hold opens its Info.
private struct MarketPickerRow: View {
    let item: TypeListRow
    let subtitle: String?
    let onSelect: (TypeID) -> Void

    var body: some View {
        Button {
            onSelect(item.id)
        } label: {
            PickerTypeRow(row: item, subtitle: subtitle)
        }
        .contextMenu {
            // A plain `TypeInfoView`: the item is not in the fit yet, so there are no in-fit
            // values.
            NavigationLink("Info", value: DatabaseRoute.type(item.id))
        }
        .hudRowButton(PickerTypeRow.rowStyle(isCurrent: false))
    }
}

/// The words under a list of modules.
private enum ModulePickerFootnote {
    /// The list is shorter than the catalogue only by what cannot be put on this hull at all.
    static let items = Text("Only what cannot fit this hull at all is hidden. CPU and power grid are not checked here — an item that does not fit yet shows up red in the editor. Touch and hold for Info.")
}

private extension TypeListRow {
    /// Base CPU and power grid, `26 tf · 92 MW`; either alone when the item has only one, `nil`
    /// when it has neither (a rig, a subsystem).
    var cpuAndPowerText: String? {
        let parts = [cpu.map { String(localized: "\($0.resourceFigure) tf", comment: "Unit: teraflops (CPU), number then unit") }, power.map { String(localized: "\($0.resourceFigure) MW", comment: "Unit: megawatts (powergrid), number then unit") }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `5 m³ · 5 Mbit/s each`: what one drone of the type costs; either alone when the SDE has only
    /// one, `nil` when it has neither.
    var droneFiguresText: String? {
        let parts = [volume.map { String(localized: "\($0.resourceFigure) m³", comment: "Unit: cubic metres, number then unit") }, droneBandwidth.map { String(localized: "\($0.resourceFigure) Mbit/s each", comment: "Drone bandwidth per drone, number then unit") }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Search results, narrowed to this kind and hull like the browse tree; flat and by relevance.
private struct MarketPickerSearchResultsView: View {
    @LiteQuery private var results: [TypeListRow]
    let pick: MarketPick
    let searchText: String
    let onSelect: (TypeID) -> Void

    init(query: SQLQuery<TypeListRow>?, pick: MarketPick, searchText: String, onSelect: @escaping (TypeID) -> Void) {
        _results = LiteQuery(query)
        self.pick = pick
        self.searchText = searchText
        self.onSelect = onSelect
    }

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            HUDList {
                if let budget = pick.budget {
                    PickerBudgetPanel(budget: budget)
                }
                HUDListSection(results, row: { item in
                    MarketPickerRow(item: item, subtitle: pick.subtitle(of: item), onSelect: onSelect)
                }, header: {
                    HUDSectionHeader(Text("Results · \(results.count)"))
                }, footer: {
                    HUDFootnote(pick.searchFootnote)
                })
            }
        }
    }
}

// MARK: - Drones and fighters

/// What the fit has left of what a drone or a fighter costs, as it stands when the sheet opens.
private enum PickerBudget {
    case drones(bay: Resource, bandwidth: Resource)
    /// `slots` are the squadron type's own.
    case fighters(hangar: Resource, slots: SlotCapacity)
}

/// `DRONE BAY FREE 50 / 125 m³` and `BANDWIDTH FREE 25 / 75 Mbit/s`, or the fighter hangar and the
/// squadron type's slots. The free amount is the figure with the total beside it; it turns
/// `danger` once the fit is past that budget, and an overdrawn bay shows zero, not a negative.
private struct PickerBudgetPanel: View {
    let budget: PickerBudget

    /// A card of its own in the picker's `HUDList`: one row, the strip, which pads its own cells.
    var body: some View {
        HUDListSection {
            HUDStatStrip(items: items, unitCase: nil)
                .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 0))
        }
    }

    private var items: [HUDStatStrip.Item] {
        switch budget {
        case let .drones(bay, bandwidth):
            [cell(id: 0, label: Text("Drone bay free"), resource: bay, unit: "m³"),
             cell(id: 1, label: Text("Bandwidth free"), resource: bandwidth, unit: "Mbit/s")]
        case let .fighters(hangar, slots):
            [cell(id: 0, label: Text("Hangar free"), resource: hangar, unit: "m³"),
             HUDStatStrip.Item(
                 id: 1,
                 label: Text("Slots free"),
                 value: Text(verbatim: "\(max(slots.available, 0))"),
                 color: slots.isOverloaded ? .hudDanger : .hudInk,
                 unit: Text(verbatim: "/ \(slots.total)")
             )]
        }
    }

    private func cell(id: Int, label: Text, resource: Resource, unit: String) -> HUDStatStrip.Item {
        HUDStatStrip.Item(
            id: id,
            label: label,
            value: Text(verbatim: max(resource.available, 0).resourceFigure),
            color: resource.isOverloaded ? .hudDanger : .hudInk,
            unit: Text(verbatim: "/ \(resource.total.resourceFigure) \(unit)")
        )
    }
}

/// The two footnotes of the drone screens: what adding does, and what it does not stop.
private enum DronePickerFootnote {
    /// A stack, and in space.
    static let added = Text("A drone is added as a full stack of 5 and launched into space.")
    /// The budget is a report, not a gate.
    static let overBudget = Text("A stack bigger than the free bay or bandwidth can still be added; the editor shows it in red.")
}

/// The root of the ammo picker: the module's charges, or search results in their place.
private struct ChargePickerBrowser: View {
    let sde: SDEDatabase
    let groups: [GroupID]
    let size: UInt8?
    let loaded: TypeID?
    let moduleName: String
    let sameTypeCount: Int
    let searchText: String
    @Binding var appliesToAll: Bool
    let onSelect: (TypeID) -> Void

    init(sde: SDEDatabase, groups: [GroupID], size: UInt8?, loaded: TypeID?, moduleName: String, sameTypeCount: Int,
         searchText: String, appliesToAll: Binding<Bool>, onSelect: @escaping (TypeID) -> Void) {
        self.sde = sde
        self.groups = groups
        self.size = size
        self.loaded = loaded
        self.moduleName = moduleName
        self.sameTypeCount = sameTypeCount
        self.searchText = searchText
        _appliesToAll = appliesToAll
        self.onSelect = onSelect
    }

    var body: some View {
        if searchText.isEmpty {
            ChargePickerListView(
                query: FittingBrowser.charges(inGroups: groups, size: size),
                loaded: loaded,
                moduleName: moduleName,
                sameTypeCount: sameTypeCount,
                appliesToAll: $appliesToAll,
                searchText: "",
                onSelect: onSelect
            )
        } else {
            ChargePickerListView(
                query: sde.pattern(searchText).map {
                    FittingBrowser.charges(inGroups: groups, size: size, matching: $0)
                },
                loaded: loaded,
                moduleName: moduleName,
                sameTypeCount: sameTypeCount,
                appliesToAll: $appliesToAll,
                searchText: searchText,
                onSelect: onSelect
            )
        }
    }
}

/// The ammo picker's body: every charge the module's groups and size accept, by meta tier (search
/// results flat), under the "Apply to All" button when the fit holds more than one such module.
private struct ChargePickerListView: View {
    @LiteQuery private var charges: [TypeListRow]
    let loaded: TypeID?
    let moduleName: String
    let sameTypeCount: Int
    @Binding var appliesToAll: Bool
    let searchText: String
    let onSelect: (TypeID) -> Void

    init(query: SQLQuery<TypeListRow>?, loaded: TypeID?, moduleName: String,
         sameTypeCount: Int, appliesToAll: Binding<Bool>, searchText: String, onSelect: @escaping (TypeID) -> Void) {
        _charges = LiteQuery(query)
        self.loaded = loaded
        self.moduleName = moduleName
        self.sameTypeCount = sameTypeCount
        _appliesToAll = appliesToAll
        self.searchText = searchText
        self.onSelect = onSelect
    }

    var body: some View {
        if !searchText.isEmpty, charges.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            HUDList {
                if sameTypeCount > 1 {
                    ApplyToAllButton(count: sameTypeCount, moduleName: moduleName, isOn: $appliesToAll)
                }
                if searchText.isEmpty {
                    TypeListSections(rows: charges, order: .ascending, headsEverySection: true) { charge, _ in
                        chargeRow(charge)
                    }
                } else {
                    HUDListSection(charges, row: { charge in
                        chargeRow(charge)
                    }, header: {
                        HUDSectionHeader(Text("Results · \(charges.count)"))
                    })
                }
            }
        }
    }

    @ViewBuilder
    private func chargeRow(_ charge: TypeListRow) -> some View {
        let isCurrent = charge.id == loaded
        Button {
            onSelect(charge.id)
        } label: {
            PickerTypeRow(row: charge, isCurrent: isCurrent)
        }
        .contextMenu {
            // The charge is not loaded yet, so there are no in-fit values.
            NavigationLink("Info", value: DatabaseRoute.type(charge.id))
        }
        .hudRowButton(PickerTypeRow.rowStyle(isCurrent: isCurrent))
    }
}

/// `Apply to All 3 Heavy Electron Blaster II`: a full-width pill that, once on, sends the charge
/// the player taps next to every module of the type instead of this one.
///
/// A switch rather than an action: there is no charge to apply until one is picked. Outlined in
/// the accent; on, it fills with a checkmark and a line under it says what the next tap does.
private struct ApplyToAllButton: View {
    let count: Int
    let moduleName: String
    @Binding var isOn: Bool

    /// A block of the picker's `HUDList` of its own: the pill as a bare row, the line about the
    /// next tap as the section's footnote.
    var body: some View {
        Section {
            Button {
                isOn.toggle()
            } label: {
                HStack(spacing: 8) {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    Text("Apply to All \(count) \(moduleName)")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.hudAccent)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, HUDMetrics.gutter)
                .background(Color.hudAccent.opacity(isOn ? 0.14 : 0), in: .capsule)
                .overlay { Capsule().strokeBorder(Color.hudAccent.opacity(isOn ? 0.6 : 0.35), lineWidth: 1) }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOn ? Text("On") : Text("Off"))
            .accessibilityAddTraits(.isToggle)
            .hudBareRow()
        } footer: {
            if isOn {
                HUDFootnote("The charge you pick next is loaded into all \(count) of them.")
                    .hudListFooter()
            }
        }
    }
}

/// The variations sheet's outer half: resolves the type's own family root before the family can
/// be listed.
///
/// `FittingBrowser.variationRoot(of:)` returns the type's own row, not the root:
/// `variationParentID` is `nil` on the root and the root's id on every variant, so the root is
/// `rootID ?? id`, worked out before `variations(ofRoot:)` can be built.
private struct ModulePickerVariationsView: View {
    let kind: DogmaItemKind
    let typeID: TypeID
    let rigSize: UInt8?
    let structureHull: Bool
    let allowed: [TypeID]
    let onSelect: (TypeID) -> Void

    @LiteQuery private var root: VariationRootRow?

    init(kind: DogmaItemKind, typeID: TypeID, rigSize: UInt8?, structureHull: Bool, allowed: [TypeID], onSelect: @escaping (TypeID) -> Void) {
        self.kind = kind
        self.typeID = typeID
        self.rigSize = rigSize
        self.structureHull = structureHull
        self.allowed = allowed
        self.onSelect = onSelect
        _root = LiteQuery(FittingBrowser.variationRoot(of: typeID))
    }

    var body: some View {
        if let root {
            ModulePickerVariationsListView(
                root: root.rootID ?? root.id,
                currentTypeID: typeID,
                kind: kind,
                allowed: allowed,
                rigSize: rigSize,
                structureHull: structureHull,
                onSelect: onSelect
            )
        } else {
            ProgressView()
        }
    }
}

/// The variations sheet's inner half: the family itself, once its root is known. Flat, like the
/// charge list. The type already in the fit is checkmarked.
private struct ModulePickerVariationsListView: View {
    @LiteQuery private var variations: [TypeListRow]
    let currentTypeID: TypeID
    let onSelect: (TypeID) -> Void

    init(root: TypeID, currentTypeID: TypeID, kind: DogmaItemKind, allowed: [TypeID], rigSize: UInt8?, structureHull: Bool,
         onSelect: @escaping (TypeID) -> Void) {
        _variations = LiteQuery(FittingBrowser.variations(ofRoot: root, kind: kind, allowed: allowed, rigSize: rigSize,
                                                         structureHull: structureHull))
        self.currentTypeID = currentTypeID
        self.onSelect = onSelect
    }

    var body: some View {
        HUDList {
            HUDListSection(variations, row: { variant in
                let isCurrent = variant.id == currentTypeID
                Button {
                    onSelect(variant.id)
                } label: {
                    // The row of the other pickers: the tier is the badge, no chevron since a tap
                    // picks. The subtitle is the item's base CPU and power grid, the two figures a
                    // family is chosen between.
                    PickerTypeRow(row: variant, subtitle: variant.cpuAndPowerText,
                                  isCurrent: isCurrent)
                }
                .contextMenu {
                    // The item as it stands outside the fit, with no in-fit values.
                    NavigationLink("Info", value: DatabaseRoute.type(variant.id))
                }
                .hudRowButton(PickerTypeRow.rowStyle(isCurrent: isCurrent))
            }, header: {
                HUDSectionHeader(Text("Variations · \(variations.count)"))
            })
        }
    }
}

#Preview {
    ModulePickerView(content: .items(kind: .hi, rigSize: nil, structureHull: false, allowed: [], slotName: "High slot", hullName: "Vexor")) { _ in }
        .environment(SDEStore())
}

#Preview("Drones") {
    ModulePickerView(content: .drones(allowed: [], hullName: "Vexor",
                                      bay: Resource(used: 75, total: 125),
                                      bandwidth: Resource(used: 50, total: 75))) { _ in }
        .environment(SDEStore())
}

#Preview("Fighters") {
    ModulePickerView(content: .fighters(squadron: .light, allowed: [], hullName: "Thanatos",
                                        hangar: Resource(used: 20_000, total: 75_000),
                                        slots: SlotCapacity(used: 1, total: 3))) { _ in }
        .environment(SDEStore())
}

#Preview("Ammo") {
    ModulePickerView(content: .charges(groups: [], size: nil, loaded: nil, moduleName: "Heavy Electron Blaster II",
                                       sameTypeCount: 3)) { _ in }
        .environment(SDEStore())
}

#Preview("Variations") {
    // Damage Control II (2048).
    ModulePickerView(content: .variations(kind: .low, typeID: 2048, rigSize: nil, structureHull: false, allowed: [])) { _ in }
        .environment(SDEStore())
}
