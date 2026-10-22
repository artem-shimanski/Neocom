import SwiftUI
import WidgetKit

/// A job's progress: a pill track with the fill in a state colour, or — for a job that is
/// paused — the `warn` hatch, the same one a paused skill level wears.
///
/// Unlike `HUDResourceBar` the fill is full strength: it says where a job is, not how much of a
/// budget is spent, and it is the one thing a list of jobs is read by.
///
/// The Lock Screen widget draws a skill's progress with it too: there the colours follow the
/// rendering mode (`HUDInk`) and the fill joins the widget's accent group.
struct HUDJobProgressBar: View {
    /// 0…1; out of range is clamped.
    var fraction: Double
    var color: Color = .hudAccent
    var isPaused = false
    var height: CGFloat = 6

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = HUDInk(renderingMode)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                ink.surfaceRaised
                Group {
                    if isPaused {
                        HUDHatch()
                    } else {
                        (ink.isFullColor ? color : .white).widgetAccentable()
                    }
                }
                .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityValue(Text(min(max(fraction, 0), 1), format: .percent.precision(.fractionLength(0))))
    }
}
