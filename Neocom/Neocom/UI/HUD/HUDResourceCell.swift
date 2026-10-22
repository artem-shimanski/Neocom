import SwiftUI

/// A resource against its budget as one cell: the label and `used/total` on a line, a
/// `HUDResourceBar` under them. Over budget turns the figure and the bar `danger`.
struct HUDResourceCell: View {
    let title: Text
    var used: Double
    var total: Double
    /// Printed after the pair (`125/125 m³`), only where there is one.
    var unit: String?
    /// Whether the figure reads `danger`; by default, past the total.
    var isOverloaded: Bool?

    var body: some View {
        let isOver = isOverloaded ?? (used > total)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                title
                    .font(.hudMicro)
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // No spaces around the slash; a unit only where there is one.
                Text(verbatim: "\(used.resourceFigure)/\(total.resourceFigure)\(unit ?? "")")
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(isOver ? Color.hudDanger : Color.hudInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
            }
            HUDResourceBar(used: used, total: total, height: 6)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Resource cell") {
    HUDList {
        HUDListSection("Command Center") {
            HStack(spacing: 14) {
                HUDResourceCell(title: Text(verbatim: "CPU"), used: 7592, total: 21_315)
                HUDResourceCell(title: Text(verbatim: "Powergrid"), used: 17_400, total: 17_000)
            }
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))
        }
    }
}
