import LiteRow
import LiteRowUI
import SwiftUI

/// Search results: types whose name matches, most relevant first. The whole catalogue is
/// searched, independent of where the browser stands.
struct TypeSearchView: View {
    let searchText: String

    @LiteQuery private var results: [TypeSearchRow]

    init(query: SQLQuery<TypeSearchRow>?, searchText: String) {
        self.searchText = searchText
        _results = LiteQuery(query)
    }

    var body: some View {
        Group {
            if results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                HUDList {
                    HUDListSection(results, row: { result in
                        NavigationLink(value: DatabaseRoute.type(result.id)) {
                            HUDTypeRow(typeID: result.id,
                                       name: result.name,
                                       subtitle: Text(result.groupName))
                        }
                        .hudRowButton(HUDTypeRow.rowStyle)
                        .hudTypeContextMenu(typeID: result.id, name: result.name)
                    }, header: {
                        HUDSectionHeader(Text("Results · \(results.count)"))
                    })
                }
            }
        }
    }
}
