import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// Settings › Trade Hubs: the player's own hubs, which the region picker offers right after the
/// five built-in ones (`MarketRegionPreference.userHubSystemIDs`), and the built-in ones under
/// them, read-only.
///
/// A hub is a solar system. Picking it reads prices in its region, and the region chip names the
/// hub after the region.
struct TradeHubsView: View {
    @Environment(MarketSheet.self) private var market

    @State private var editMode: EditMode = .inactive
    @State private var isAdding = false

    var body: some View {
        let preference = market.regions
        SDESectionView { _ in
            TradeHubsList(preference: preference, isEditing: editMode.isEditing) {
                isAdding = true
            }
            .environment(\.editMode, $editMode)
        }
        .hudScreen()
        .navigationTitle("Trade Hubs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
                .fontWeight(editMode.isEditing ? .semibold : .regular)
                .disabled(preference.userHubSystemIDs.isEmpty && !editMode.isEditing)
            }
        }
        .onChange(of: preference.userHubSystemIDs.isEmpty) { _, isEmpty in
            if isEmpty { editMode = .inactive }
        }
        .sheet(isPresented: $isAdding) {
            TradeHubPickerSheet()
        }
    }
}

private struct TradeHubsList: View {
    let preference: MarketRegionPreference
    let isEditing: Bool
    let onAdd: () -> Void

    @LiteQuery private var systems: [MarketSystemRow]

    init(preference: MarketRegionPreference, isEditing: Bool, onAdd: @escaping () -> Void) {
        self.preference = preference
        self.isEditing = isEditing
        self.onAdd = onAdd
        let ids = MarketRegionPreference.tradeHubs.map(\.solarSystemID) + preference.userHubSystemIDs
        _systems = LiteQuery(MarketBrowser.systems(ids.map(MarketFormat.systemID)))
    }

    var body: some View {
        let byID = Dictionary(systems.map { (Int64($0.id.rawValue), $0) }, uniquingKeysWith: { first, _ in first })
        let builtIn = MarketRegionPreference.tradeHubs.compactMap { byID[$0.solarSystemID] }
        let mine = preference.userHubSystemIDs.compactMap { byID[$0] }
        // The rows are placed by hand rather than by `HUDListSection`: `onDelete` belongs to the
        // `ForEach` itself, which that section would take apart.
        let cardCount = mine.count + (isEditing ? 0 : 1)

        HUDList {
            Section {
                ForEach(Array(mine.enumerated()), id: \.element.id) { index, system in
                    TradeHubRow(system: system)
                        .environment(\.hudRowPosition, HUDRowPosition(index: index, count: cardCount))
                }
                .onDelete { offsets in
                    preference.removeUserHubs(offsets.map { Int64(mine[$0].id.rawValue) })
                }
                if !isEditing {
                    HUDAddRow(title: "Add Hub", action: onAdd)
                        .environment(\.hudRowPosition, HUDRowPosition(index: cardCount - 1, count: cardCount))
                }
            } header: {
                HUDSectionHeader(Text("Your Hubs · \(mine.count)")).hudListHeader()
            } footer: {
                HUDFootnote("Swipe a hub to the left to remove it. A hub is a solar system: prices come from its region.")
                    .hudListFooter()
            }

            HUDListSection {
                ForEach(builtIn) { system in
                    TradeHubRow(system: system)
                }
            } header: {
                HUDSectionHeader(Text("Built In · \(MarketRegionPreference.tradeHubs.count)"))
            } footer: {
                HUDFootnote("The five empire hubs are always there. Yours come right after them in the Market Region picker.")
            }
        }
    }
}

/// A hub: the system, and under it its region with the system's security.
private struct TradeHubRow: View {
    let system: MarketSystemRow

    var body: some View {
        HUDRowTitle(title: Text(verbatim: system.name),
                    subtitle: HUDPlaceBlock.system(name: system.regionName, security: system.securityStatus),
                    font: .hudTileTitle,
                    subtitleCase: nil)
            .hudRow(.subtitled)
    }
}

/// Adds a hub: a search over the systems of every market region, the hubs already there left out.
/// Opens the database itself.
private struct TradeHubPickerSheet: View {
    @Environment(MarketSheet.self) private var market
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            SDESectionView { database in
                let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    HUDList(isTransparent: true) {
                        Section {
                            HUDFootnote("Search for a solar system by its name. Its region becomes the hub's market.")
                                .hudBareRow()
                        }
                    }
                } else {
                    TradeHubSearchResults(pattern: database.pattern(trimmed), searchText: trimmed,
                                          preference: market.regions) { systemID in
                        market.regions.addUserHub(systemID)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Add Hub")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Solar system"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
        }
    }
}

private struct TradeHubSearchResults: View {
    let searchText: String
    let preference: MarketRegionPreference
    let onSelect: (Int64) -> Void

    @LiteQuery private var systems: [MarketSystemRow]

    /// A card row on the sheet's glass.
    private static let rowStyle = HUDRowStyle(background: HUDRowStyle.sheet.background,
                                              border: HUDRowStyle.sheet.border,
                                              divider: HUDRowStyle.sheet.divider,
                                              minHeight: 56, verticalPadding: 8)

    init(pattern: FTS5Pattern?, searchText: String, preference: MarketRegionPreference,
         onSelect: @escaping (Int64) -> Void) {
        self.searchText = searchText
        self.preference = preference
        self.onSelect = onSelect
        _systems = LiteQuery(pattern.map { MarketBrowser.searchSystems($0) })
    }

    var body: some View {
        let found = systems.filter { !preference.isHub(Int64($0.id.rawValue)) }
        if found.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            HUDList(isTransparent: true) {
                HUDListSection(found, row: { system in
                    Button {
                        onSelect(Int64(system.id.rawValue))
                    } label: {
                        HUDRowTitle(title: Text(verbatim: system.name),
                                    subtitle: HUDPlaceBlock.system(name: system.regionName,
                                                                   security: system.securityStatus),
                                    font: .hudTileTitle,
                                    subtitleCase: nil)
                            .hudRow(Self.rowStyle)
                    }
                    .hudRowButton(Self.rowStyle)
                }, header: {
                    HUDSectionHeader(Text("Systems"))
                })
            }
        }
    }
}
