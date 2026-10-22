import SwiftUI

/// A small outlined mark after a name: mono caps in a state colour, ringed in the same colour
/// at reduced strength (`FINAL BLOW`, `TOP DAMAGE`, `NPC`). Not a button (`HUDLinkChip`) and not
/// a tier (`HUDMetaBadge`).
struct HUDOutlineTag: View {
    let text: Text
    var color: Color = .hudAccent

    var body: some View {
        text
            .font(.hudMicro)
            .tracking(1)
            .textCase(.uppercase)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1)
            }
    }

    /// Marks the demo pilot wherever its name is shown.
    static var demo: HUDOutlineTag {
        HUDOutlineTag(text: Text("Demo"))
    }
}

#Preview("Outline tag") {
    HStack(spacing: 6) {
        HUDOutlineTag(text: Text(verbatim: "Final Blow"))
        HUDOutlineTag(text: Text(verbatim: "Top Damage"))
        HUDOutlineTag(text: Text(verbatim: "NPC"), color: .hudInkMuted)
        HUDOutlineTag.demo
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudSurface)
}
