import SwiftUI

// The content layer of the Neocom HUD design system: flat opaque panels with 1 pt borders,
// uppercase mono labels, figures in a monospaced face, colour reserved for state. The chrome —
// navigation bar, toolbar, sheets, menus, the main action — stays system Liquid Glass and is
// only tinted, never redrawn.

/// Shared layout metrics of the HUD content layer: gutters, spacing, radii, minimum row height.
enum HUDMetrics {
    /// Screen side gutter and panel horizontal padding.
    static let gutter: CGFloat = 16
    /// Between sections on a screen.
    static let sectionSpacing: CGFloat = 18
    /// Between a section header and its content, and between tiles in a grid.
    static let headerSpacing: CGFloat = 10
    /// A section header's text and rule sit this far inside their card's edge.
    static let headerFaceInset: CGFloat = 4
    static let panelRadius: CGFloat = 20
    static let tileRadius: CGFloat = 16
    static let rowMinHeight: CGFloat = 52
    /// The widest a `HUDList`'s cards grow on Mac; a wider column centres them.
    static let maxReadableWidth: CGFloat = 900
}

#Preview("Metrics") {
    HUDList {
        Section {
            Text(verbatim: "Gutter \(HUDMetrics.gutter) · Section \(HUDMetrics.sectionSpacing) · Header \(HUDMetrics.headerSpacing)")
                .hudRow()
            Text(verbatim: "Panel radius \(HUDMetrics.panelRadius) · Tile radius \(HUDMetrics.tileRadius) · Row min height \(HUDMetrics.rowMinHeight)")
                .hudRow()
        }
    }
}
