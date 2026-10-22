import SwiftUI

/// A glowing state dot, a name in the state's ink and a muted detail, in mono caps on one line
/// (`● TRANQUILITY · 24 318 ONLINE`). A line of text, not a chip: it sits on the screen
/// background and reads as a status announcement (`.updatesFrequently`).
struct HUDStatusLine: View {
    let color: Color
    let title: Text
    /// The title's ink: `ink` while all is well, the state colour otherwise.
    var titleColor: Color = .hudInk
    var detail: Text?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color, radius: 3)
            title.foregroundStyle(titleColor)
            if let detail {
                detail.foregroundStyle(Color.hudInkMuted)
            }
        }
        .font(.hudLabel)
        .tracking(1.5)
        .textCase(.uppercase)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.leading, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("Status line") {
    VStack(alignment: .leading, spacing: 16) {
        HUDStatusLine(color: .hudOk, title: Text(verbatim: "Tranquility"), detail: Text(verbatim: "· 24 318 online"))
        HUDStatusLine(color: .hudWarn, title: Text(verbatim: "Tranquility"), titleColor: .hudWarn,
                      detail: Text(verbatim: "· VIP · developers only"))
        HUDStatusLine(color: .hudWarn, title: Text(verbatim: "Downtime"), titleColor: .hudWarn,
                      detail: Text(verbatim: "· back about 11:15 EVE"))
        HUDStatusLine(color: .hudDanger, title: Text(verbatim: "Tranquility offline"), titleColor: .hudDanger)
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudBg)
}
