import SwiftUI

/// One row of a card of effects between two things: `FROM → TO` in mono with the amount at the
/// trailing edge, and the carrier of the effect under it in the body face. An effect inside a
/// panel, where the receiver is implied, is `HUDEffectLine`.
struct HUDFlowRow: View {
    let source: Text
    let target: Text
    let detail: Text
    /// The signed figure (`+59.2 HP/s`), or `nil` when the engine gives no number.
    let amount: Text?
    var tone: HUDEffectTone = .gain

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                source
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tone.color)
                    .accessibilityLabel(Text("to"))
                target
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let amount {
                    amount
                        .tracking(0)
                        .foregroundStyle(tone.color)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .font(HUDFont.mono(12, weight: .regular, relativeTo: .caption))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Color.hudInk)
            detail
                .font(HUDFont.display(14, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(Color.hudInkBodyMuted)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 8))
    }
}

#Preview("Flow row") {
    HUDList {
        HUDListSection(Text(verbatim: "Remote Effects · 3")) {
            HUDFlowRow(source: Text(verbatim: "Exequror"), target: Text(verbatim: "Vexor"),
                       detail: Text(verbatim: "Medium Remote Armor Repairer II"),
                       amount: Text(verbatim: "+59.2 HP/s"))
            HUDFlowRow(source: Text(verbatim: "Exequror"), target: Text(verbatim: "Thorax"),
                       detail: Text(verbatim: "Medium Remote Capacitor Transmitter II"),
                       amount: Text(verbatim: "+22.5 GJ/s"))
            HUDFlowRow(source: Text(verbatim: "Thorax"), target: Text(verbatim: "Vexor"),
                       detail: Text(verbatim: "Stasis Webifier II"),
                       amount: nil, tone: .neutral)
        }
    }
}
