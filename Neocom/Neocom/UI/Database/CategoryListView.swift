import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// Top level of the browser: the published categories, with how much sits under each.
struct CategoryListView: View {
    @LiteQuery private var categories: [CategoryListRow]

    init(query: SQLQuery<CategoryListRow>?) {
        _categories = LiteQuery(query)
    }

    var body: some View {
        HUDList {
            HUDListSection(categories, row: { category in
                NavigationLink(value: DatabaseRoute.category(category.id)) {
                    HUDCountRow(name: category.name, count: category.typeCount)
                }
                .hudRowButton()
            }, header: {
                HUDSectionHeader(Text("Categories · \(categories.count)"))
            })
        }
    }
}

/// Second level: the groups of one category.
struct GroupListView: View {
    @LiteQuery private var header: CategoryHeader?
    @LiteQuery private var groups: [GroupListRow]

    init(categoryID: CategoryID) {
        _header = LiteQuery(SDEBrowser.header(ofCategory: categoryID))
        _groups = LiteQuery(SDEBrowser.groups(inCategory: categoryID))
    }

    var body: some View {
        HUDList {
            HUDListSection(groups, row: { group in
                NavigationLink(value: DatabaseRoute.group(group.id)) {
                    HUDCountRow(name: group.name, count: group.typeCount)
                }
                .hudRowButton()
            }, header: {
                HUDSectionHeader(Text("Groups · \(groups.count)"))
            })
        }
        .navigationTitle(header?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One level of a tree: a name, how much sits under it, and the chevron. Shared by every tree in
/// the app; a branch with an icon of its own (a market group) puts it before the name, and the row
/// grows to a type row's height.
struct HUDCountRow<Count: BinaryInteger, Icon: View>: View {
    let name: String
    let count: Count
    private let icon: Icon?

    init(name: String, count: Count, @ViewBuilder icon: () -> Icon) {
        self.name = name
        self.count = count
        self.icon = icon()
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
            Text(name)
                .font(.hudBody)
                .frame(minWidth: 100, alignment: .leading)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(Int(count), format: .number)
                .font(.hudCaption)
                .foregroundStyle(Color.hudInkMuted)
            HUDChevron()
        }
        // 48pt high, set by the height alone, no vertical padding.
        .hudRow(icon == nil ? HUDRowStyle(minHeight: 48, verticalPadding: 0) : HUDTypeRow.rowStyle)
    }
}

extension HUDCountRow where Icon == Never {
    init(name: String, count: Count) {
        self.name = name
        self.count = count
        self.icon = nil
    }
}
