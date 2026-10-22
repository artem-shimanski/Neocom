import SwiftUI
import WidgetKit

/// The diagonal `warn` hatch of a paused level segment.
///
/// In a widget the colours follow its rendering mode (`HUDInk`).
struct HUDHatch: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ground = HUDInk(renderingMode).warnHatch
        let stripes = HUDInk(renderingMode).warnStripe
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))
            let step: CGFloat = 6
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(stripe, with: .color(stripes), lineWidth: 2.2)
                x += step
            }
        }
    }
}
