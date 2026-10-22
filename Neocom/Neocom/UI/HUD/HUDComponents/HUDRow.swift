import SwiftUI

/// The look of one row of a panel card: its fill, its border, the divider above it, its padding
/// and minimum height. Where the row sits in its card — and so which corners it rounds and which
/// edges it borders — is not part of the style: `HUDListSection` works it out for every row it
/// holds.
struct HUDRowStyle {
    var background: Color = .hudSurface
    var border: Color = .hudLine
    /// The 1pt line above every row but the card's first.
    var divider: Color = .hudLineSubtle
    var horizontalPadding: CGFloat = HUDMetrics.gutter
    var minHeight: CGFloat = HUDMetrics.rowMinHeight
    var verticalPadding: CGFloat = 8
    /// Extra padding on the side of the row that is the card's edge — above the card's first row,
    /// below its last — on top of `verticalPadding`. For a card of tight rows (the readouts) that
    /// needs more air against its border than between its rows.
    var cardEdgePadding: CGFloat = 0
    var cornerRadius: CGFloat = HUDMetrics.panelRadius

    static let `default` = HUDRowStyle()
    /// A `HUDReadoutRow`, and a link whose label is one (`hudRowButton(.readout)`).
    static let readout = HUDRowStyle(minHeight: 0, verticalPadding: 10, cardEdgePadding: 4)
    /// A card on a sheet, which is system glass rather than the screen background: a translucent
    /// veil of the ink colour (white in dark) instead of the opaque surface, so the sheet material
    /// shows through.
    static let sheet = HUDRowStyle(
        background: Color.primary.opacity(0.07),
        border: Color.primary.opacity(0.10),
        divider: Color.primary.opacity(0.08)
    )

    /// The row's share of the card outline at `position`: rounded at the card's top and bottom,
    /// square where the row meets its neighbours.
    func shape(at position: HUDRowPosition) -> UnevenRoundedRectangle {
        let top = position.isFirst ? cornerRadius : 0
        let bottom = position.isLast ? cornerRadius : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        )
    }
}

/// Where a row sits in its card. The card's first row carries its top edge — rounded corners and
/// the outer border — the last carries its bottom edge, and a row of its own carries both.
enum HUDRowPosition: Hashable, Sendable {
    case first, middle, last, only

    init(isFirst: Bool, isLast: Bool) {
        switch (isFirst, isLast) {
        case (true, true): self = .only
        case (true, false): self = .first
        case (false, true): self = .last
        case (false, false): self = .middle
        }
    }

    init(index: Int, count: Int) {
        self.init(isFirst: index == 0, isLast: index == count - 1)
    }

    var isFirst: Bool { self == .first || self == .only }
    var isLast: Bool { self == .last || self == .only }
}

extension EnvironmentValues {
    /// The position of a `hudRow` in its card, for a row built already knowing it (the data form
    /// of `HUDListSection`, or a row placed by hand). `.only` by default: a row nobody placed is
    /// drawn as a card of its own, closed on every side, rather than as an open-ended slice of a
    /// card that is not there.
    @Entry var hudRowPosition: HUDRowPosition = .only
}

extension View {
    /// One row of a panel card in a `HUDList`: the padding and minimum height from `style`, and —
    /// via `listRowBackground` — its share of the card itself, cut by `\.hudRowPosition`: the
    /// fill, the outer border on the edges that face outside the card, the rounded corners at the
    /// card's top and bottom, and the divider above every row but the first. Outside a List there
    /// is no row background to set, and only the padding applies.
    func hudRow(_ style: HUDRowStyle = .default) -> some View {
        modifier(HUDRowModifier(style: style))
    }

    /// The list-row half of `hudRow` alone — zero row insets, no separator, the card's share as
    /// the row background — for the outermost view of a row whose padding sits deeper inside it.
    ///
    /// A List reads row traits only off the row's outermost view: inside a `Button` or a
    /// `NavigationLink` label they are lost, and the row falls back to the system cell — default
    /// insets, a plain background, no card. So a tappable row keeps `hudRow` in its label (the
    /// padding, the touch height, the pressed highlight across the whole row) and takes the
    /// cell from here, on the button itself; `hudRowButton()` does both halves of the button.
    func hudRowCell(_ style: HUDRowStyle = .default) -> some View {
        modifier(HUDRowCellModifier(style: style))
    }
}

private struct HUDRowModifier: ViewModifier {
    var style: HUDRowStyle
    @Environment(\.hudRowPosition) private var position
    @Environment(\.hudRowPlacementIsDeferred) private var placementIsDeferred

    func body(content: Content) -> some View {
        // Placed later, the row does not know its position yet: the container adds the card-edge
        // padding around it (`hudRowPosition(_:)` on a `Subview`).
        let edge = placementIsDeferred ? 0 : style.cardEdgePadding
        content
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)
            .padding(.top, position.isFirst ? edge : 0)
            .padding(.bottom, position.isLast ? edge : 0)
            .frame(maxWidth: .infinity, minHeight: style.minHeight, alignment: .leading)
            .contentShape(Rectangle())
            .hudRowCell(style)
    }
}

private struct HUDRowCellModifier: ViewModifier {
    var style: HUDRowStyle
    @Environment(\.hudRowPosition) private var position
    @Environment(\.hudRowPlacementIsDeferred) private var placementIsDeferred

    func body(content: Content) -> some View {
        let row = content
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .containerValue(\.hudRowStyle, style)
        if placementIsDeferred {
            row
        } else {
            // Clipped to the card, so a pressed highlight (`HUDRowButtonStyle`) keeps its corners.
            row
                .clipShape(style.shape(at: position))
                .listRowBackground(HUDRowCellBackground(style: style, position: position))
        }
    }
}

extension EnvironmentValues {
    /// Set by a container that resolves its rows first and places them itself
    /// (`hudRowPosition(_:)` on a `Subview`): a resolved row is fixed — its row background is a
    /// trait no second `listRowBackground` replaces, and an environment value applied to it does
    /// not reach its content — so a row resolved under this flag sets neither its background, nor
    /// its card-edge padding, nor its clip to the card, and the container wraps all three around
    /// it.
    @Entry var hudRowPlacementIsDeferred = false
}

extension ContainerValues {
    /// The style of a `hudRow`, for a container that places the row after it is resolved.
    @Entry var hudRowStyle: HUDRowStyle? = nil
}

extension Subview {
    /// This resolved row drawn at `position` in its card: its card-edge padding, its clip to the
    /// card and its row background, from the style the row left in its container values. The
    /// rows must have been resolved with `\.hudRowPlacementIsDeferred` on, so they set neither
    /// themselves. A subview that is not a `hudRow` is returned as is.
    @ViewBuilder
    func hudRowPosition(_ position: HUDRowPosition) -> some View {
        if let style = containerValues.hudRowStyle {
            self
                .padding(.top, position.isFirst ? style.cardEdgePadding : 0)
                .padding(.bottom, position.isLast ? style.cardEdgePadding : 0)
                .clipShape(style.shape(at: position))
                .listRowBackground(HUDRowCellBackground(style: style, position: position))
        } else {
            self
        }
    }
}

/// The cell background of a `hudRow`. The card outline is one rounded rectangle stroked inside
/// its bounds (so the 1pt border is never half-clipped), stretched past the edges this cell
/// shares with its neighbours and clipped to the cell — so those edges get no border at all, and
/// the only line between two rows is the next one's divider: exactly 1pt everywhere.
private struct HUDRowCellBackground: View {
    var style: HUDRowStyle
    var position: HUDRowPosition

    /// How far the outline runs past a hidden edge: enough to take its stroke out of the cell.
    private static let overhang: CGFloat = 2

    var body: some View {
        let shape = style.shape(at: position)
        var hidden: Edge.Set = []
        if !position.isFirst { hidden.insert(.top) }
        if !position.isLast { hidden.insert(.bottom) }

        return ZStack(alignment: .top) {
            shape.fill(style.background)
                .padding(hidden, -Self.overhang)
            if !position.isFirst {
                Rectangle()
                    .fill(style.divider)
                    .frame(height: 1)
            }
            shape.strokeBorder(style.border, lineWidth: 1)
                .padding(hidden, -Self.overhang)
        }
        .clipped()
    }
}

#Preview("Panel rows") {
    HUDList {
        HUDListSection(Text("Implants · 4")) {
            Text(verbatim: "First row — the card's top edge").hudRow()
            Text(verbatim: "Second row, divider above it").hudRow()
            Text(verbatim: "Short middle row").hudRow(HUDRowStyle(minHeight: 32, verticalPadding: 4))
            Text(verbatim: "Last row — the card's bottom edge").hudRow()
        }

        Section {
            Text(verbatim: "A row placed by hand as the top of a card").hudRow()
                .environment(\.hudRowPosition, .first)
            Text(verbatim: "…and as its bottom").hudRow()
                .environment(\.hudRowPosition, .last)
        }

        Section {
            Text(verbatim: "A row nobody placed is a whole card.").hudRow()
        }
    }
}
