import SwiftUI

/// A trend in a few dozen points, small enough for a caption line: one polyline stretched over
/// the frame the caller gives it, from the lowest point at the bottom to the highest at the
/// top. No axes and no labels — the figure beside it says what the trend is; this only shows
/// its shape. Decorative for VoiceOver for the same reason.
///
/// Fewer than two points draw nothing; a flat series is a line through the middle.
struct HUDSparkline: View {
    let values: [Double]
    var color: Color = .hudAccent
    var lineWidth: CGFloat = 1.4

    var body: some View {
        SparklineShape(values: values, inset: lineWidth / 2)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .accessibilityHidden(true)
    }
}

private struct SparklineShape: Shape {
    var values: [Double]
    /// Half the stroke, kept clear at the top and the bottom so the extremes are not cut.
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        guard values.count >= 2, let low = values.min(), let high = values.max() else { return Path() }
        let span = high - low
        let height = max(rect.height - 2 * inset, 0)
        let step = rect.width / CGFloat(values.count - 1)
        return Path { path in
            for (index, value) in values.enumerated() {
                let fraction: CGFloat = span > 0 ? CGFloat((value - low) / span) : 0.5
                let x: CGFloat = rect.minX + CGFloat(index) * step
                let y: CGFloat = rect.maxY - inset - fraction * height
                let point = CGPoint(x: x, y: y)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

#Preview("Sparkline") {
    let values: [Double] = (0..<30).map { (index: Int) -> Double in
        let wave: Double = sin(Double(index) / 3) * 0.4
        return 9.2 + wave + Double(index % 4) * 0.1
    }
    HStack(spacing: 10) {
        Text(verbatim: "Market · Heimatar").font(.hudMicro).tracking(1.5).textCase(.uppercase)
            .foregroundStyle(Color.hudInkMuted)
        Spacer()
        HUDSparkline(values: values).frame(width: 60, height: 18)
        Text(verbatim: "−5.6% 30D").font(.hudMicro).foregroundStyle(Color.hudInkBodyMuted)
    }
    .padding(HUDMetrics.gutter)
    .hudScreen()
}
