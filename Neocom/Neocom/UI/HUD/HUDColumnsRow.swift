import SwiftUI

/// A readout with two value columns and the head row that names them.
///
/// The columns have a fixed width shared with `HUDColumnsHeader`, so figures stay aligned from
/// row to row.
struct HUDColumnsRow: View {
    /// One value column, wide enough for the widest head (`SUSTAINED`) and a four-figure rate.
    static let columnWidth: CGFloat = 80

    let label: Text
    /// A quiet second line under the label, for a row with no figures.
    var note: Text?
    /// One per column, in the head's order.
    var values: [Text]
    var ink: Color = .hudInk
    /// A row that sums the ones above it: full-ink label, heavier face.
    var isEmphasized = false
    /// The card divider above the row. `.clear` for the first row under a `HUDColumnsHeader`,
    /// `hudLineLeader` above a total.
    var divider: Color = .hudLineSubtle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                label
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(isEmphasized ? Color.hudInk : Color.hudInkMuted)
                if let note {
                    note
                        .font(.hudMicro)
                        .foregroundStyle(Color.hudInkFaint)
                }
            }
            .layoutPriority(1)
            HUDLeader()
                .frame(minWidth: 12)
            ForEach(values.indices, id: \.self) { index in
                values[index]
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: Self.columnWidth, alignment: .trailing)
            }
        }
        .font(isEmphasized ? HUDFont.mono(13, weight: .semibold, relativeTo: .subheadline) : .hudReadout)
        .hudRow(HUDRowStyle(divider: divider, minHeight: 0, verticalPadding: 10))
        .accessibilityElement(children: .combine)
    }
}

/// The head over `HUDColumnsRow`: the captions in the same widths, with nothing over the label
/// column. No divider comes between it and the first row; give that row `divider: .clear`.
struct HUDColumnsHeader: View {
    /// The caption face's letter spacing, given back at the trailing edge.
    private static let tracking: CGFloat = 1.5

    let columns: [Text]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Spacer(minLength: 0)
            ForEach(columns.indices, id: \.self) { index in
                columns[index]
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: HUDColumnsRow.columnWidth, alignment: .trailing)
            }
        }
        .font(.hudMicro)
        .tracking(Self.tracking)
        .textCase(.uppercase)
        .foregroundStyle(Color.hudInkMuted)
        // Tracking is also added after the last letter; taking it back off the trailing edge
        // keeps a right-aligned caption over its column.
        .padding(.trailing, -Self.tracking)
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 8))
        .accessibilityHidden(true)
    }
}

#Preview {
    HUDList {
        HUDListSection("Repair") {
            HUDColumnsHeader(columns: [Text("Peak"), Text("Sustained")])
            HUDColumnsRow(label: Text("Shield passive regen"),
                          values: [Text(verbatim: "8.6"), Text(verbatim: "8.6")],
                          divider: .clear)
            HUDColumnsRow(label: Text("Shield boost"), note: Text("No module fitted"),
                          values: [Text(verbatim: "—"), Text(verbatim: "—")],
                          ink: .hudInkFaint)
            HUDColumnsRow(label: Text("Armor repair"),
                          values: [Text(verbatim: "74.2"), Text(verbatim: "41.8")])
            HUDColumnsRow(label: Text("Total"),
                          values: [Text(verbatim: "82.8"), Text(verbatim: "50.4")],
                          isEmphasized: true, divider: .hudLineLeader)
        }
    }
}
