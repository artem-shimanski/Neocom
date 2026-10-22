import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// Top of the market tree: its roots, with how much sits under each.
struct MarketGroupListView: View {
    @LiteQuery private var groups: [MarketGroupListRow]

    init(query: SQLQuery<MarketGroupListRow>?) {
        _groups = LiteQuery(query)
    }

    var body: some View {
        HUDList {
            HUDListSection(groups, row: { group in
                MarketGroupRowView(group: group)
            }, header: {
                HUDSectionHeader(Text("Market Groups · \(groups.count)"))
            })
        }
    }
}

/// Every level below the first: the sub-groups of a market group and the items filed on it. Both
/// are shown, as a group such as "Ship SKINs" has hundreds of sub-groups and items of its own.
struct MarketGroupView: View {
    @LiteQuery private var header: MarketGroupHeader?
    @LiteQuery private var groups: [MarketGroupListRow]
    @LiteQuery private var types: [TypeListRow]

    init(groupID: MarketGroupID) {
        _header = LiteQuery(SDEBrowser.header(ofMarketGroup: groupID))
        _groups = LiteQuery(SDEBrowser.marketGroups(inParent: groupID))
        _types = LiteQuery(SDEBrowser.types(inMarketGroup: groupID))
    }

    var body: some View {
        HUDList {
            if !groups.isEmpty {
                HUDListSection(groups, row: { group in
                    MarketGroupRowView(group: group, fallbackIconID: header?.iconID)
                }, header: {
                    HUDSectionHeader(Text("Groups · \(groups.count)"))
                })
            }
            TypeListSections(rows: types)
        }
        .navigationTitle(header?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One market group, drawn identically by the roots list and the group screen. A group with no
/// icon shows its parent's (`fallbackIconID`), else a folder glyph. Generic over where it leads:
/// the database pushes a `MarketRoute`, the hull picker its own level of the same tree.
struct MarketGroupRowView<Value: Hashable>: View {
    let group: MarketGroupListRow
    var fallbackIconID: IconID?
    let value: Value

    init(group: MarketGroupListRow, fallbackIconID: IconID? = nil, value: Value) {
        self.group = group
        self.fallbackIconID = fallbackIconID
        self.value = value
    }

    var body: some View {
        NavigationLink(value: value) {
            HUDCountRow(name: group.name, count: group.typeCount) {
                HUDIconPlate(group.iconID, fallbackIconID, placeholder: "folder")
            }
        }
        .hudRowButton()
    }
}

extension MarketGroupRowView where Value == MarketRoute {
    init(group: MarketGroupListRow, fallbackIconID: IconID? = nil) {
        self.init(group: group, fallbackIconID: fallbackIconID, value: .group(group.id))
    }
}

/// Where a row of the market tree leads. Items lead to `TypeInfoView` through `DatabaseRoute`.
enum MarketRoute: Hashable {
    case group(MarketGroupID)

    @ViewBuilder var destination: some View {
        switch self {
        case let .group(id): MarketGroupView(groupID: id)
        }
    }
}
