import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// The Database section: the whole static data export, reached by walking one of two trees or by
/// searching by name. The trees end at the same item screen and are switched on one screen.
struct DatabaseView: View {
    /// Remembered across launches.
    @AppStorage("databaseHierarchy") private var hierarchy: DatabaseHierarchy = .categories
    @State private var searchText = ""

    var body: some View {
        SDESectionView { database in
            DatabaseBrowser(sde: database, hierarchy: hierarchy, searchText: searchText)
                // `DatabaseRoute` is registered for every section by `SDESectionView`; the market tree's route
                // is registered here.
                .navigationDestination(for: MarketRoute.self) { route in
                    route.destination
                        .liteDatabase(database.database)
                }
        }
        .hudScreen()
        .navigationTitle("Database")
        // The switch stands where the title would be, so the title goes inline.
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: Text("Item name"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Browse By", selection: $hierarchy) {
                    ForEach(DatabaseHierarchy.allCases) { hierarchy in
                        Text(hierarchy.title).tag(hierarchy)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

/// The two ways down to an item.
enum DatabaseHierarchy: String, CaseIterable, Identifiable {
    /// Category, group, item: the whole export, as the inventory files it.
    case categories
    /// The market tree, as the in-game market shows it; a type with no market group is not in it.
    case marketGroups

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .categories: "Categories"
        case .marketGroups: "Market Groups"
        }
    }

    var systemImage: String {
        switch self {
        case .categories: "square.stack.3d.up"
        case .marketGroups: "cart"
        }
    }
}

/// The root of the chosen tree, or search results in its place. Split out because `@LiteQuery`
/// takes the query as an argument.
private struct DatabaseBrowser: View {
    let sde: SDEDatabase
    let hierarchy: DatabaseHierarchy
    let searchText: String

    var body: some View {
        if searchText.isEmpty {
            switch hierarchy {
            case .categories:
                CategoryListView(query: SDEBrowser.categories())
            case .marketGroups:
                MarketGroupListView(query: SDEBrowser.marketGroups(inParent: nil))
            }
        } else {
            // Search covers the whole catalogue regardless of the tree. `pattern` returns nil when the input
            // has no searchable token (punctuation only); `@LiteQuery` answers a nil query with an empty
            // result.
            TypeSearchView(
                query: sde.pattern(searchText).map { SDEBrowser.search($0) },
                searchText: searchText
            )
        }
    }
}

/// Where a row of the category tree leads. One type for all three levels, so the section needs a
/// single `navigationDestination`.
enum DatabaseRoute: Hashable {
    case category(CategoryID)
    case group(GroupID)
    case type(TypeID)
    case certificate(CertificateID)
    /// The market of a type, in the region the app prices items in.
    case market(TypeID)

    @ViewBuilder var destination: some View {
        switch self {
        case let .category(id): GroupListView(categoryID: id)
        case let .group(id): TypeListView(groupID: id)
        case let .type(id): TypeInfoView(typeID: id)
        case let .certificate(id): CertificateInfoView(certificateID: id)
        case let .market(id): MarketTypeView(typeID: id)
        }
    }
}

#Preview {
    NavigationStack {
        DatabaseView()
    }
    .environment(SDEStore())
}
