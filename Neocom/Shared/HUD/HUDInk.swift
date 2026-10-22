import SwiftUI
import WidgetKit

/// The HUD colour tokens for the way a widget is rendered.
///
/// In full colour (the app, and a widget on an ordinary Home Screen) they are the tokens
/// themselves, light and dark by their own appearances. Rendered tinted or on the Lock Screen,
/// the system keeps only each layer's opacity — an opaque plate would come out solid — so each
/// token is white at the opacity it stands for there, and `warn` no longer stands out: a state
/// is never told by colour alone.
struct HUDInk {
    let isFullColor: Bool

    init(_ renderingMode: WidgetRenderingMode) {
        isFullColor = renderingMode == .fullColor
    }

    var ink: Color { isFullColor ? .hudInk : .white.opacity(0.96) }
    var muted: Color { isFullColor ? .hudInkMuted : .white.opacity(0.62) }
    var bodyMuted: Color { isFullColor ? .hudInkBodyMuted : .white.opacity(0.78) }
    var accent: Color { isFullColor ? .hudAccent : .white }
    var warn: Color { isFullColor ? .hudWarn : .white.opacity(0.96) }
    var warnNote: Color { isFullColor ? .hudWarnNoteInk : .white.opacity(0.78) }
    var surfaceRaised: Color { isFullColor ? .hudSurfaceRaised : .white.opacity(0.16) }
    var line: Color { isFullColor ? .hudLine : .white.opacity(0.24) }
    var lineSubtle: Color { isFullColor ? .hudLineSubtle : .white.opacity(0.16) }
    var lineLeader: Color { isFullColor ? .hudLineLeader : .white.opacity(0.40) }
    var warnHatch: Color { isFullColor ? .hudWarnHatch : .white.opacity(0.18) }
    var warnStripe: Color { isFullColor ? .hudWarnStripe : .white.opacity(0.9) }
}
