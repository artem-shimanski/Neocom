import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

struct TypeListView: View {
    @LiteQuery private var header: GroupHeader?
    @LiteQuery private var types: [TypeListRow]

    init(groupID: GroupID) {
        _header = LiteQuery(SDEBrowser.header(ofGroup: groupID))
        _types = LiteQuery(SDEBrowser.types(inGroup: groupID))
    }

    var body: some View {
        HUDList {
            TypeListSections(rows: types)
        }
        .navigationTitle(header?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}
