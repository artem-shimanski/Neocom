import SwiftUI

/// A small outlined label that is a button: mono caps in `accent` with a chevron after it. The
/// header's `SKILLS · ALL V`, which reads as a setting and opens the screen that changes it.
struct HUDLinkChip: View {
    let title: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                title
                    .font(.hudLabel)
                    .tracking(1)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.hudAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.hudAccent.opacity(0.35), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Link chip") {
    HStack(spacing: 8) {
        Text(verbatim: "Skills").font(.hudLabel).tracking(2).textCase(.uppercase).foregroundStyle(Color.hudInkMuted)
        Spacer()
        HUDLinkChip(title: Text("All V")) {}
    }
    .padding(.horizontal, HUDMetrics.gutter + 4)
    .padding(.top, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.hudBg.ignoresSafeArea())
}
