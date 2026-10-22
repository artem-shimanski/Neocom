import SwiftUI

/// One node of a production flow as a small tile: kind, product, rate, load bar and a note.
/// Tiles of one tier stand in a grid; a storage between tiers is a `HUDChainHub`, the flow
/// between rows a `HUDChainConnector`.
///
/// `isDimmed` marks a tile off the traced path, `isSelected` outlines it in `accent`; `warn`
/// marks a node that needs attention.
struct HUDChainTile: View {
    /// `ECU · 2 HEADS`, `BASIC ×3`.
    let tag: Text
    let name: Text
    /// `19 500/h`.
    let rate: Text
    /// Program done (extractors) or time busy (factories), 0…1; `nil` draws no bar.
    var progress: Double?
    /// `PROGRAM 16%`, `BUSY 45% · SHORT`.
    var note: Text?
    var tone: HUDTone = .normal
    var isSelected = false
    var isDimmed = false

    static let radius: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let stateColor: Color = tone == .normal ? .hudAccent : .hudWarn
        VStack(alignment: .leading, spacing: 3) {
            tag
                .font(HUDFont.mono(9, weight: .regular, relativeTo: .caption2))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            name
                .font(HUDFont.display(13, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.hudInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            rate
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .foregroundStyle(Color.hudInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let progress {
                HUDResourceBar(fraction: progress, color: stateColor, height: 3)
            }
            if let note {
                note
                    .font(HUDFont.mono(9, weight: .regular, relativeTo: .caption2))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(tone == .normal ? Color.hudInkMuted : Color.hudWarn)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
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

#Preview("Chain tile") {
    HUDList {
        Section {
            Grid(horizontalSpacing: 8) {
                GridRow {
                    HUDChainTile(tag: Text(verbatim: "ECU · 2 heads"), name: Text(verbatim: "Base Metals"),
                                 rate: Text(verbatim: "19 500/h"), progress: 0.16, note: Text(verbatim: "Program 16%"))
                    HUDChainTile(tag: Text(verbatim: "Basic ×2"), name: Text(verbatim: "Precious Metals"),
                                 rate: Text(verbatim: "36/h"), progress: 0.45, note: Text(verbatim: "Busy 45% · short"),
                                 tone: .warn)
                    HUDChainTile(tag: Text(verbatim: "Basic ×1"), name: Text(verbatim: "Water"),
                                 rate: Text(verbatim: "32/h"), progress: 0.8, note: Text(verbatim: "Busy 80%"),
                                 isSelected: true)
                }
                GridRow {
                    HUDChainTile(tag: Text(verbatim: "Advanced ×1"), name: Text(verbatim: "Mechanical Parts"),
                                 rate: Text(verbatim: "4.5/h"), progress: 0.9, note: Text(verbatim: "Busy 90%"),
                                 isDimmed: true)
                    Color.clear
                    Color.clear
                }
            }
            .hudBareRow()
        }
    }
}
