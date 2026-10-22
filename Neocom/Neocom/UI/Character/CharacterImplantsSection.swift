import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// The implants in the clone the character is wearing right now.
/// They come from `/implants`, which the training snapshot already fetches; the attribute bonuses
/// above are computed from the same list.
struct CharacterImplantsSection: View {
    let implants: [TypeID]

    @LiteQuery private var names: [TypeNameRow]

    init(implants: [TypeID]) {
        self.implants = implants
        _names = LiteQuery(SDEBrowser.typeNames(of: implants))
    }

    var body: some View {
        // An empty "Implants" would read as data that failed to arrive.
        if !implants.isEmpty {
            HUDListSection(Text("Implants · \(implants.count)")) {
                // The order ESI sent, which is the slot order.
                ForEach(implants, id: \.self) { implant in
                    ImplantRow(implant: implant, name: names.first { $0.id == implant }?.name)
                }
            }
        }
    }
}

/// One implant: its icon, its name, and the way to its type screen.
/// It takes the name rather than looking it up, so a list of implants can name all of them with one
/// query.
struct ImplantRow: View {
    let implant: TypeID
    let name: String?

    var body: some View {
        NavigationLink(value: DatabaseRoute.type(implant)) {
            HStack(spacing: 12) {
                HUDItemIcon(typeID: implant, size: 32)
                Text(name ?? "")
                    .font(.hudBody)
                Spacer(minLength: 0)
                HUDChevron()
            }
            .hudRow()
        }
        .hudRowButton()
    }
}
