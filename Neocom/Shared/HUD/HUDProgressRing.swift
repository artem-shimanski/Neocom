import SwiftUI
import WidgetKit

/// A closed ring with the progress drawn clockwise from the top, round-capped: the circular
/// Lock Screen widget's current skill. White on a faint white track, the way the Lock Screen
/// renders anyway; the arc joins the widget's accent group.
struct HUDProgressRing: View {
    /// 0…1; out of range is clamped, 0 draws the track alone.
    var fraction: Double
    var lineWidth: CGFloat = 6
    /// The arc's opacity: dimmed for a paused queue.
    var arcOpacity: Double = 1

    var body: some View {
        let fraction = min(max(fraction, 0), 1)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: lineWidth)
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.white.opacity(arcOpacity),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
        }
        .padding(lineWidth / 2)
        .accessibilityElement()
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}
