import SwiftUI

/// One addressee as a 30 pt capsule on the raised plate: a kind glyph and a name. With
/// `onRemove` it ends in a small cross.
///
/// A `.warn` chip rings itself in `warn` and may carry a short mono `marker` after the name.
/// Several wrap in a `HUDWrapLayout`.
struct HUDTokenChip: View {
    let title: Text
    var systemImage: String?
    /// What the glyph means, for VoiceOver (`Character`, `Mailing list`).
    var kindLabel: Text?
    var tone: HUDTone = .normal
    /// A short mono tag after the name, in the tone's ink (`CSPA`).
    var marker: Text?
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.hudInkMuted)
                    .accessibilityLabel(kindLabel ?? Text(verbatim: ""))
                    .accessibilityHidden(kindLabel == nil)
            }
            title
                .font(HUDFont.display(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Color.hudInk)
                .lineLimit(1)
            if let marker {
                marker
                    .font(.hudMicro)
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(tone == .normal ? Color.hudInkMuted : tone.ink)
                    .lineLimit(1)
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.hudInkMuted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove"))
            }
        }
        .padding(.leading, systemImage == nil ? 11 : 9)
        .padding(.trailing, onRemove == nil ? 11 : 5)
        .frame(height: 30)
        .background(Color.hudSurfaceRaised, in: Capsule())
        .overlay { Capsule().strokeBorder(tone == .normal ? Color.hudLine : tone.ink, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Token chip") {
    HUDWrapLayout(spacing: 6) {
        HUDTokenChip(title: Text(verbatim: "Artem Valiant"), systemImage: "person")
        HUDTokenChip(title: Text(verbatim: "Bram Ironvale"), systemImage: "person")
        HUDTokenChip(title: Text(verbatim: "Drone Pilots Guild"), systemImage: "list.bullet")
        HUDTokenChip(title: Text(verbatim: "Rens Traders"), systemImage: "building.2", onRemove: {})
        HUDTokenChip(title: Text(verbatim: "Ysolde Marrow"), systemImage: "person", tone: .warn,
                     marker: Text(verbatim: "CSPA"), onRemove: {})
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudBg)
}
