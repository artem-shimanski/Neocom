import LiteRowUI
import SDEKit
import SwiftUI

/// An icon the static data export carries itself — a market group's — on the same plate as a
/// type icon (`HUDItemIcon`).
///
/// `iconIDs` are tried in order and the first the database has a picture for is drawn, so a
/// caller can name a fallback after the icon it wants (a group with none borrows its parent's).
/// With none of them there, `placeholder` (an SF Symbol) is drawn on the plate so the row still
/// says what kind of thing it is; without one the bare plate stays, as an image-server icon that
/// never loads leaves it, and the names in a list stay aligned.
struct HUDIconPlate: View {
    let iconIDs: [IconID]
    var placeholder: String?
    var size: CGFloat = 40

    @Environment(\.liteDatabase) private var database

    init(_ iconIDs: IconID?..., placeholder: String? = nil, size: CGFloat = 40) {
        self.iconIDs = iconIDs.compactMap(\.self)
        self.placeholder = placeholder
        self.size = size
    }

    var body: some View {
        if let image = SDEIconImages.image(for: iconIDs, in: database) {
            Image(uiImage: image).resizable().scaledToFill()
                .hudImagePlate(size: size)
        } else if let placeholder {
            HUDSymbolPlate(systemImage: placeholder, size: size)
        } else {
            Color.clear
                .hudImagePlate(size: size)
        }
    }
}
