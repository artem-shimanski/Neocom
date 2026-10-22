import SwiftUI

/// One row of a type picker: the item, a caller-worded `subtitle`, its tier, and a mark if it is
/// the one already in the fit. No chevron: a tap picks instead of navigating.
struct PickerTypeRow: View {
    let row: TypeListRow
    var subtitle: String?
    var isCurrent = false

    var body: some View {
        HStack(spacing: 12) {
            HUDItemIcon(typeID: row.id, size: 40)
            HUDRowTitle(title: Text(row.name), subtitle: subtitle.map { Text(verbatim: $0) }, subtitleCase: nil)
                .frame(minWidth: 120, alignment: .leading)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if let badge = row.metaBadgeText {
                HUDMetaBadge(text: Text(verbatim: badge), color: row.metaBadgeColor)
            }
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.hudAccent)
                    .accessibilityLabel("Current")
            }
        }
        .hudRow(Self.rowStyle(isCurrent: isCurrent))
    }

    /// The row's cell, current tint included. The tint is the cell's own fill, so it reaches the
    /// card's border and rounded corners; the button the row labels takes the same style
    /// (`hudRowButton(_:)`).
    static func rowStyle(isCurrent: Bool) -> HUDRowStyle {
        HUDRowStyle(
            background: isCurrent ? Color.hudSurface.mix(with: .hudAccent, by: 0.06) : .hudSurface,
            minHeight: 52,
            verticalPadding: 6
        )
    }
}
