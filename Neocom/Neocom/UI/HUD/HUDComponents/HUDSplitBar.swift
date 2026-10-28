import SwiftUI

/// Two shares of one whole side by side in a thin capsule: what was sold against what was
/// bought. The parts are scaled to their sum; an empty whole draws the track alone.
struct HUDSplitBar: View {
    let leading: Double
    let trailing: Double
    var leadingColor: Color = .hudAccent
    var trailingColor: Color = .hudLineLeader
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let total = max(leading, 0) + max(trailing, 0)
            let first = total > 0 ? proxy.size.width * max(leading, 0) / total : 0
            HStack(spacing: 0) {
                Rectangle().fill(leadingColor).frame(width: first)
                Rectangle().fill(total > 0 ? trailingColor : Color.hudLine)
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

#Preview("Split bar") {
    VStack(spacing: 16) {
        HUDSplitBar(leading: 27.7e6, trailing: 23e6)
        HUDSplitBar(leading: 4e6, trailing: 0)
        HUDSplitBar(leading: 0, trailing: 0)
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudSurface)
}
