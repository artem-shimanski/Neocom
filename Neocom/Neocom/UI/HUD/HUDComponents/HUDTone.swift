import SwiftUI

/// The tone of a panel or tile: its border colour says which state it is in.
enum HUDTone {
    case normal
    case warn
    case danger

    var border: Color {
        switch self {
        case .normal: .hudLine
        case .warn: .hudWarnLine
        case .danger: .hudDangerLine
        }
    }

    /// The tone's own ink, for a mark or a ring that says the state rather than frames it.
    var ink: Color {
        switch self {
        case .normal: .hudInk
        case .warn: .hudWarn
        case .danger: .hudDanger
        }
    }
}

#Preview("Tones") {
    VStack(spacing: HUDMetrics.sectionSpacing) {
        HUDPanel(tone: .normal) { Text(verbatim: "Normal").hudRow() }
        HUDPanel(tone: .warn) { Text(verbatim: "Warn").hudRow() }
        HUDPanel(tone: .danger) { Text(verbatim: "Danger").hudRow() }
    }
    .padding(.horizontal, HUDMetrics.gutter)
    .background(Color.hudBg.ignoresSafeArea())
}
