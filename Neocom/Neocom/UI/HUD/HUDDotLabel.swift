import SwiftUI

/// A small filled circle in a data colour, with a dark hairline ring so near-white and
/// near-black colours stay visible. Without a colour it takes `hudMarkNeutral`.
struct HUDColorDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .overlay { Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A colour dot and a name in mono caps: `● FLEET OPS  ● KEEP`.
struct HUDDotLabel: View {
    let title: Text
    let color: Color
    var dotSize: CGFloat = 7

    var body: some View {
        HStack(spacing: 5) {
            HUDColorDot(color: color, size: dotSize)
            title
                .textCase(.uppercase)
                .lineLimit(1)
        }
    }
}

#Preview("Dot label") {
    HStack(spacing: 12) {
        HUDDotLabel(title: Text(verbatim: "Fleet Ops"), color: .orange)
        HUDDotLabel(title: Text(verbatim: "Keep"), color: .yellow)
        HUDDotLabel(title: Text(verbatim: "Inbox"), color: .hudMarkNeutral)
    }
    .font(.hudLabel)
    .tracking(1)
    .foregroundStyle(Color.hudInkBodyMuted)
    .padding(HUDMetrics.gutter)
    .background(Color.hudBg)
}
