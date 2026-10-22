import SwiftUI

/// A storage in a production flow, drawn across the width between two rows of `HUDChainTile`s:
/// its name, current fill, fill forecast, and what goes in and out.
///
/// Selects and dims like a tile. `warn` colours its bar and status.
struct HUDChainHub: View {
    /// `2 · STORAGE`.
    let tag: Text
    let name: Text
    /// `FULL IN 21h 50m`, `30% → 36%`.
    let status: Text
    /// Fill now, 0…1.
    var fill: Double
    /// Fill at the end of the window, 0…1.
    var forecast: Double?
    /// Under the bar on the left: `11 836 / 12 000 m³`, `→ 4 320 m³`.
    var leading: Text?
    /// Under the bar on the right: `IN 29 700 · OUT 28 200 /h`.
    var trailing: Text?
    var tone: HUDTone = .normal
    var isSelected = false
    var isDimmed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HUDMetrics.tileRadius, style: .continuous)
        let stateColor: Color = tone == .normal ? .hudAccent : .hudWarn
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                tag
                    .font(HUDFont.mono(9, weight: .regular, relativeTo: .caption2))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
                name
                    .font(HUDFont.display(14, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.hudInk)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                status
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .textCase(.uppercase)
                    .foregroundStyle(tone == .normal ? Color.hudInkBodyMuted : Color.hudWarn)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            HUDResourceBar(fraction: fill, color: stateColor, height: 6, forecast: forecast)
            if leading != nil || trailing != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    leading
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    trailing
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(HUDFont.mono(10, weight: .regular, relativeTo: .caption2))
                .foregroundStyle(Color.hudInkMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hudSurface, in: shape)
        .overlay {
            shape.strokeBorder(isSelected ? Color.hudAccent : tone.border, lineWidth: 1)
        }
        .contentShape(shape)
        .opacity(isDimmed ? 0.3 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Chain hub") {
    HUDList {
        Section {
            VStack(spacing: 8) {
                HUDChainHub(tag: Text(verbatim: "2 · Storage"), name: Text(verbatim: "Storage Facility"),
                            status: Text(verbatim: "Full in 21h 50m"), fill: 0.986, forecast: 1,
                            leading: Text(verbatim: "11 836 / 12 000 m³"),
                            trailing: Text(verbatim: "IN 29 700 · OUT 28 200 /h"), tone: .warn)
                HUDChainHub(tag: Text(verbatim: "4 · Storage"), name: Text(verbatim: "Storage Facility"),
                            status: Text(verbatim: "30% → 36%"), fill: 0.30, forecast: 0.36,
                            leading: Text(verbatim: "→ 4 320 m³"), trailing: Text(verbatim: "IN 188 · OUT 144 /h"),
                            isSelected: true)
                HUDChainHub(tag: Text(verbatim: "6 · Launchpad"), name: Text(verbatim: "Launchpad"),
                            status: Text(verbatim: "17%"), fill: 0.17, isDimmed: true)
            }
            .hudBareRow()
        }
    }
}
