import SwiftUI

/// A thin capsule filled from the leading edge to `fraction` (0...1), with the quantity it
/// stands for on the trailing side (`7 / 10 LEFT`). `tint` fills it, muted for a finished order.
struct HUDOrderFillBar: View {
    let fraction: Double
    var tint: Color = .hudAccent
    /// Written beside the bar, trailing; `nil` for the bar alone.
    var caption: Text?

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.hudLine)
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(1, max(0, fraction)))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
            if let caption {
                caption
                    .font(.hudMicro)
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

#Preview("Order fill bar") {
    VStack(spacing: 16) {
        HUDOrderFillBar(fraction: 0.7, caption: Text(verbatim: "7 / 10 left"))
        HUDOrderFillBar(fraction: 0.3, tint: .hudLineLeader, caption: Text(verbatim: "3 / 10 left"))
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudBg)
}
