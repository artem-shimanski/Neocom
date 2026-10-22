import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// The hull picker behind the "My Fits" + button, the fleet sheet's `Empty Hull…` and the
/// killboard's ship-type filter: browse the market tree or search, fittable hulls only.
///
/// Hulls are `FittingBrowser.hullIDs`: every ship and, with `includesStructures`, every structure
/// with a slot to fit. The tree is the market's ("Ships", "Structures") with every branch and
/// count narrowed to hulls. A sheet gets a fresh environment, so it has its own `NavigationStack`
/// and `SDESectionView` and opens the database itself.
struct ShipPickerView: View {
    var includesStructures = true
    /// Called once with the hull's id and the name shown in the picker, right before dismissal.
    var onSelect: (TypeID, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            SDESectionView { database in
                ShipPickerBrowser(sde: database, searchText: searchText,
                                  includesStructures: includesStructures, onSelect: select)
                    .navigationDestination(for: MarketGroupID.self) { groupID in
                        // Reapplied: a pushed destination does not reliably inherit `liteDatabase`.
                        HullMarketGroupView(groupID: groupID, includesStructures: includesStructures,
                                            onSelect: select)
                            .liteDatabase(database.database)
                    }
            }
            .hudScreen()
            .navigationTitle(includesStructures ? "Select a Hull" : "Select a Ship")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: includesStructures ? Text("Hull name") : Text("Ship name"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func select(_ typeID: TypeID, named name: String) {
        onSelect(typeID, name)
        dismiss()
    }
}

/// The picker's root: the market roots with hulls under them, or search results.
private struct ShipPickerBrowser: View {
    let sde: SDEDatabase
    let searchText: String
    let includesStructures: Bool
    let onSelect: (TypeID, String) -> Void

    var body: some View {
        if searchText.isEmpty {
            HullMarketRootsView(includesStructures: includesStructures)
        } else {
            ShipSearchResultsView(
                query: sde.pattern(searchText).map {
                    FittingBrowser.hulls(matching: $0, includingStructures: includesStructures)
                },
                searchText: searchText,
                onSelect: onSelect
            )
        }
    }
}

private struct HullMarketRootsView: View {
    @LiteQuery private var groups: [MarketGroupListRow]

    init(includesStructures: Bool) {
        _groups = LiteQuery(FittingBrowser.hullMarketGroups(inParent: nil, includingStructures: includesStructures))
    }

    var body: some View {
        HUDList {
            HUDListSection(groups, row: { group in
                MarketGroupRowView(group: group, value: group.id)
            }, header: {
                HUDSectionHeader(Text("Market Groups · \(groups.count)"))
            })
        }
    }
}

/// Sub-groups with hulls and the hulls filed on this group, shown together.
private struct HullMarketGroupView: View {
    @LiteQuery private var header: MarketGroupHeader?
    @LiteQuery private var groups: [MarketGroupListRow]
    @LiteQuery private var types: [TypeListRow]
    let onSelect: (TypeID, String) -> Void

    init(groupID: MarketGroupID, includesStructures: Bool, onSelect: @escaping (TypeID, String) -> Void) {
        _header = LiteQuery(SDEBrowser.header(ofMarketGroup: groupID))
        _groups = LiteQuery(FittingBrowser.hullMarketGroups(inParent: groupID, includingStructures: includesStructures))
        _types = LiteQuery(FittingBrowser.hulls(inMarketGroup: groupID, includingStructures: includesStructures))
        self.onSelect = onSelect
    }

    var body: some View {
        HUDList {
            if !groups.isEmpty {
                HUDListSection(groups, row: { group in
                    MarketGroupRowView(group: group, fallbackIconID: header?.iconID, value: group.id)
                }, header: {
                    HUDSectionHeader(Text("Groups · \(groups.count)"))
                })
            }
            TypeListSections(rows: types) { type, showsMetaGroup in
                Button {
                    onSelect(type.id, type.name)
                } label: {
                    HUDTypeRow(typeID: type.id, name: type.name,
                               subtitle: showsMetaGroup ? type.metaGroupName.map { Text($0) } : nil)
                }
                .hudRowButton(HUDTypeRow.rowStyle)
            }
        }
        .navigationTitle(header?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Search results narrowed to hulls. A few hulls are on no market group, so search is the
/// only way to them.
private struct ShipSearchResultsView: View {
    @LiteQuery private var results: [TypeSearchRow]
    let searchText: String
    let onSelect: (TypeID, String) -> Void

    init(query: SQLQuery<TypeSearchRow>?, searchText: String, onSelect: @escaping (TypeID, String) -> Void) {
        _results = LiteQuery(query)
        self.searchText = searchText
        self.onSelect = onSelect
    }

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            HUDList {
                HUDListSection(results, row: { result in
                    Button {
                        onSelect(result.id, result.name)
                    } label: {
                        HUDTypeRow(typeID: result.id, name: result.name, subtitle: Text(result.groupName))
                    }
                    .hudRowButton(HUDTypeRow.rowStyle)
                }, header: {
                    HUDSectionHeader(Text("Results · \(results.count)"))
                })
            }
        }
    }
}

#Preview {
    ShipPickerView { _, _ in }
        .environment(SDEStore())
}
