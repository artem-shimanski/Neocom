import SDEKit
import SwiftUI

/// A type icon from the EVE image server on `image-plate` — dark in dark, steel blue in light,
/// where it is also outlined with `line` so it reads as an object rather than a hole.
struct HUDItemIcon: View {
    let typeID: TypeID
    var size: CGFloat = 40

    var body: some View {
        HUDImagePlate(url: EVEImage.icon(typeID: Int64(typeID.rawValue), size: size > 32 ? 128 : 64),
                      size: size)
    }
}

#Preview("Item icon") {
    HStack(spacing: 12) {
        HUDItemIcon(typeID: TypeID(rawValue: 3074), size: 28)
        HUDItemIcon(typeID: TypeID(rawValue: 3074), size: 40)
        HUDItemIcon(typeID: TypeID(rawValue: 3074), size: 64)
    }
    .padding(.horizontal, HUDMetrics.gutter)
    .padding(.top, 8)
    .background(Color.hudBg.ignoresSafeArea())
}
