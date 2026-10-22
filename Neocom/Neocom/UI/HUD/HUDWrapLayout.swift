import SwiftUI

/// Lays its children out left to right, wrapping onto a new line when the next one does not
/// fit. Each line is as tall as its tallest child; children keep their ideal size, clipped to
/// the width offered.
///
/// With `fillsLastLine` the last child takes the rest of its line while its ideal width fits
/// there, and otherwise moves to a line of its own at full width.
struct HUDWrapLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat?
    var fillsLastLine = false

    init(spacing: CGFloat = 6, lineSpacing: CGFloat? = nil, fillsLastLine: Bool = false) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.fillsLastLine = fillsLastLine
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = arrange(subviews, width: width)
        let height = lines.map(\.height).reduce(0, +) + CGFloat(max(lines.count - 1, 0)) * (lineSpacing ?? spacing)
        let used = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for item in line.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (line.height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += line.height + (lineSpacing ?? spacing)
        }
    }

    private struct Item {
        var index: Int
        var size: CGSize
    }

    private struct Line {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            let needed = line.items.isEmpty ? size.width : line.width + spacing + size.width
            if !line.items.isEmpty, needed > width {
                lines.append(line)
                line = Line()
            }
            if fillsLastLine, index == subviews.indices.last, width.isFinite {
                size.width = line.items.isEmpty ? width : width - line.width - spacing
                size.height = subviews[index].sizeThatFits(ProposedViewSize(width: size.width, height: nil)).height
            }
            line.width = line.items.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.items.append(Item(index: index, size: size))
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}
