import SwiftUI

/// The round mark at the front of a checklist row: an outlined ring when off, filled with
/// `accent` and checked when on. Dimmed when the row cannot be changed.
///
/// The row around it is the button, so the circle hides itself from VoiceOver.
struct HUDCheckCircle: View {
    let isOn: Bool
    var isEnabled = true

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? Color.hudAccent : .clear)
            Circle()
                .strokeBorder(isOn ? Color.hudAccent : Color.hudInkFaint, lineWidth: 1.5)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.hudBg)
            }
        }
        .frame(width: 24, height: 24)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityHidden(true)
    }
}

#Preview("Check circle") {
    HStack(spacing: 16) {
        HUDCheckCircle(isOn: false)
        HUDCheckCircle(isOn: true)
        HUDCheckCircle(isOn: true, isEnabled: false)
        HUDCheckCircle(isOn: false, isEnabled: false)
    }
    .padding(HUDMetrics.gutter)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.hudBg.ignoresSafeArea())
}
