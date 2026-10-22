import SDEKit
import SwiftUI

/// One item in a HUD list: its icon on a plate, its name, an optional mono line, an optional
/// quantity, and a chevron when the row leads somewhere.
struct HUDTypeRow: View {
    /// The row's style, for the link or button that wraps it (`hudRowButton`).
    static let rowStyle = HUDRowStyle(minHeight: 56)

    let typeID: TypeID
    let name: String
    var subtitle: Text?
    /// Set after the name in figure mono (`×1 234`); the caller formats the figure.
    var quantity: Text?
    var showsChevron = true
    var iconSize: CGFloat = 40
    /// `1` for names that can run long and must keep the quantity on the row; `nil` wraps.
    var lineLimit: Int?

    var body: some View {
        HStack(spacing: 12) {
            HUDItemIcon(typeID: typeID, size: iconSize)
            HUDRowTitle(title: Text(name), subtitle: subtitle)
                .lineLimit(lineLimit)
                .frame(minWidth: 120, alignment: .leading)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if let quantity {
                quantity
                    .font(HUDFont.mono(13, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.hudInk)
                    .lineLimit(1)
                    .fixedSize()
            }
            if showsChevron {
                HUDChevron()
            }
        }
        .hudRow(Self.rowStyle)
    }
}

#Preview("Type row") {
    HUDList {
        HUDListSection {
            HUDTypeRow(typeID: TypeID(rawValue: 3074), name: "Heavy Neutron Blaster II",
                       subtitle: Text(verbatim: "Hybrid Weapon"))
            HUDTypeRow(typeID: TypeID(rawValue: 3074), name: "Heavy Neutron Blaster II",
                       subtitle: Text(verbatim: "Hybrid Weapon"), quantity: Text(verbatim: "×5"),
                       showsChevron: false, iconSize: 36, lineLimit: 1)
        }
    }
}
