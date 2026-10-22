import SwiftUI

/// The direction of an effect from another ship on the receiving one: a gain reads `ok`, a loss
/// `danger`, and an effect with no figure stays muted.
enum HUDEffectTone {
    case gain
    case loss
    case neutral

    var color: Color {
        switch self {
        case .gain: .hudOk
        case .loss: .hudDanger
        case .neutral: .hudInkMuted
        }
    }
}

/// One line of a panel's incoming-effects block: an arrow, the source, the effect and its
/// amount, all mono on one line (`← EXEQUROR  Medium Remote Armor Repairer II  +59.2 HP/s`).
/// The effect name gives way first. A card row with source and target is `HUDFlowRow`.
struct HUDEffectLine: View {
    let source: Text
    let detail: Text
    /// The signed figure (`+59.2 HP/s`), or `nil` when the engine gives no number.
    let amount: Text?
    var tone: HUDEffectTone = .gain

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            source
                .foregroundStyle(Color.hudInk)
                .lineLimit(1)
                .layoutPriority(1)
            detail
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let amount {
                amount
                    .foregroundStyle(tone.color)
                    .lineLimit(1)
                    .layoutPriority(2)
            }
        }
        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Effect line") {
    HUDList {
        Section {
            HUDPanel {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Incoming from Fleet")
                        .font(.hudMicro).tracking(1.5).textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                    HUDEffectLine(source: Text(verbatim: "Exequror"),
                                  detail: Text(verbatim: "Medium Remote Armor Repairer II"),
                                  amount: Text(verbatim: "+59.2 HP/s"))
                    HUDEffectLine(source: Text(verbatim: "Exequror"),
                                  detail: Text(verbatim: "Medium Remote Capacitor Transmitter II"),
                                  amount: Text(verbatim: "+22.5 GJ/s"))
                    HUDEffectLine(source: Text(verbatim: "Curse"),
                                  detail: Text(verbatim: "Heavy Energy Neutralizer II"),
                                  amount: Text(verbatim: "-48.0 GJ/s"), tone: .loss)
                    HUDEffectLine(source: Text(verbatim: "Thorax"),
                                  detail: Text(verbatim: "Stasis Webifier II"),
                                  amount: nil, tone: .neutral)
                }
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.vertical, 12)
            }
            .hudBareRow()
        }
    }
}
