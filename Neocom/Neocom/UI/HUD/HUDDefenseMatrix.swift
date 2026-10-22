import SwiftUI

/// The resistance matrix: the four damage types as column heads, then a row per defence layer
/// with its name, four resistances and hit points.
///
/// The column labels are printed once above the rows, so each row's `HUDDamageBlock` runs
/// label-less. Card-less: the caller makes it a row of a card (`hudRow` with zero horizontal
/// padding, as the matrix pads itself).
struct HUDDefenseMatrix: View {
    struct Layer: Identifiable {
        var id: Int
        /// `SHIELD`, `ARMOR`, `STRUCTURE`; upper-cased here.
        var title: Text
        /// EM, thermal, kinetic, explosive. `nil` is a missing resistance, drawn as a dash.
        var resistances: [Double?]
        /// The layer's hit points, already written, without a unit; the column head names it.
        var hitPoints: Text
    }

    /// Widths of the name column (64 pt) and the hit-points column (58 pt), fixed so the four
    /// damage columns align across rows.
    static let titleWidth: CGFloat = 64
    static let hitPointsWidth: CGFloat = 58

    let layers: [Layer]
    /// The head over the trailing column: `HP`, or `EHP` where the screen offers both.
    let hitPointsColumn: Text

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: HUDDamageBlock.columnSpacing, verticalSpacing: 0) {
            GridRow {
                Color.clear.frame(width: Self.titleWidth, height: 1)
                HUDDamageTypeLabels()
                hitPointsColumn
                    .font(.hudMicro)
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .frame(width: Self.hitPointsWidth, alignment: .trailing)
                    .gridColumnAlignment(.trailing)
            }
            .padding(.top, 11)
            .padding(.bottom, 10)

            ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                // The rule between layers is a row of its own: an overlay on a `GridRow` is
                // applied per cell and draws the line in pieces.
                if index > 0 {
                    GridRow {
                        Rectangle().fill(Color.hudLineSubtle)
                            .frame(height: 1)
                            .padding(.horizontal, -HUDMetrics.gutter)
                            .gridCellColumns(3)
                    }
                }
                GridRow {
                    layer.title
                        .font(.hudMicro)
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: Self.titleWidth, alignment: .leading)
                    HUDDamageBlock(values: layer.resistances, scale: .unit, numbers: .percent,
                                   showsLabels: false)
                    layer.hitPoints
                        .font(HUDFont.mono(13, weight: .semibold, relativeTo: .subheadline))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: Self.hitPointsWidth, alignment: .trailing)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, HUDMetrics.gutter)
    }
}

#Preview {
    HUDList {
        HUDListSection("Tank") {
            HUDDefenseMatrix(
                layers: [
                    .init(id: 0, title: Text("Shield"), resistances: [0.08, 0.26, 0.45, 0.54],
                          hitPoints: Text(verbatim: "1 375")),
                    .init(id: 1, title: Text("Armor"), resistances: [0.69, 0.66, 0.54, 0.45],
                          hitPoints: Text(verbatim: "2 813")),
                    .init(id: 2, title: Text("Structure"), resistances: [0.6, 0.6, nil, 0.6],
                          hitPoints: Text(verbatim: "2 090")),
                ],
                hitPointsColumn: Text("EHP"))
            .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 0))
        }
    }
}
