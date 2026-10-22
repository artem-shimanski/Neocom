import SwiftUI

/// A dashed outline of a rounded rectangle whose every corner sits on the middle of a dash.
///
/// A plain dashed stroke runs as one ribbon from wherever the path starts, so a gap often lands
/// on a corner. Here each side is stroked on its own, from the midpoint of one corner arc to the
/// midpoint of the next: the pattern is stretched to a whole number of periods per side and
/// starts half a dash in, so each side begins and ends with half a dash, and the two halves of
/// neighbouring sides meet as one dash centred on the corner. Inset like `strokeBorder`.
struct HUDDashedOutline: Shape {
    var cornerRadii: RectangleCornerRadii
    var lineWidth: CGFloat = 1
    /// The dash and the gap the pattern is stretched from.
    var dash: CGFloat = 2.5
    var gap: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        let inset = lineWidth / 2
        let box = rect.insetBy(dx: inset, dy: inset)
        guard box.width > 0, box.height > 0 else { return Path() }
        let limit = min(box.width, box.height) / 2
        func radius(_ r: CGFloat) -> CGFloat { min(max(r - inset, 0), limit) }
        let tl = radius(cornerRadii.topLeading), tr = radius(cornerRadii.topTrailing)
        let br = radius(cornerRadii.bottomTrailing), bl = radius(cornerRadii.bottomLeading)

        // One side: the second half of corner A's arc, the straight part, the first half of
        // corner B's. Angles grow clockwise on the screen (y points down).
        struct Side {
            let a: CGFloat, b: CGFloat
            let centerA: CGPoint, centerB: CGPoint
            let startAngle: Double
            let to: CGPoint
        }
        let sides = [
            Side(a: tl, b: tr, centerA: CGPoint(x: box.minX + tl, y: box.minY + tl),
                 centerB: CGPoint(x: box.maxX - tr, y: box.minY + tr), startAngle: 225,
                 to: CGPoint(x: box.maxX - tr, y: box.minY)),
            Side(a: tr, b: br, centerA: CGPoint(x: box.maxX - tr, y: box.minY + tr),
                 centerB: CGPoint(x: box.maxX - br, y: box.maxY - br), startAngle: 315,
                 to: CGPoint(x: box.maxX, y: box.maxY - br)),
            Side(a: br, b: bl, centerA: CGPoint(x: box.maxX - br, y: box.maxY - br),
                 centerB: CGPoint(x: box.minX + bl, y: box.maxY - bl), startAngle: 45,
                 to: CGPoint(x: box.minX + bl, y: box.maxY)),
            Side(a: bl, b: tl, centerA: CGPoint(x: box.minX + bl, y: box.maxY - bl),
                 centerB: CGPoint(x: box.minX + tl, y: box.minY + tl), startAngle: 135,
                 to: CGPoint(x: box.minX, y: box.minY + tl)),
        ]

        var result = Path()
        for side in sides {
            var path = Path()
            path.addRelativeArc(center: side.centerA, radius: side.a,
                                startAngle: .degrees(side.startAngle), delta: .degrees(45))
            let lineStart = path.currentPoint
            path.addLine(to: side.to)
            let straight = lineStart.map { hypot(side.to.x - $0.x, side.to.y - $0.y) } ?? 0
            path.addRelativeArc(center: side.centerB, radius: side.b,
                                startAngle: .degrees(side.startAngle + 45), delta: .degrees(45))

            let length = (side.a + side.b) * .pi / 4 + straight
            guard length > 0 else { continue }
            let periods = max(1, (length / (dash + gap)).rounded())
            let period = length / periods
            let dashLength = period * dash / (dash + gap)
            // dashPhase is the offset into the pattern at the start of the path: half a dash in
            // puts the start of the side in the middle of a dash.
            let style = StrokeStyle(lineWidth: lineWidth, dash: [dashLength, period - dashLength],
                                    dashPhase: dashLength / 2)
            result.addPath(path.strokedPath(style))
        }
        return result
    }
}

#Preview("Dashed outline") {
    VStack(spacing: 16) {
        HUDDashedOutline(cornerRadii: .init(topLeading: 5, bottomLeading: 5, bottomTrailing: 2, topTrailing: 2))
            .fill(Color.hudAccent)
            .frame(width: 60, height: 10)
        HUDDashedOutline(cornerRadii: .init(topLeading: 12, bottomLeading: 12, bottomTrailing: 12, topTrailing: 12))
            .fill(Color.hudAccent)
            .frame(width: 100, height: 40)
        HUDDashedOutline(cornerRadii: .init())
            .fill(Color.hudAccent)
            .frame(width: 50, height: 20)
    }
    .scaleEffect(3)
    .padding(80)
}
