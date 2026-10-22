import SwiftUI

/// Something a text links to, drawn as a card inside the text: a ship fitting in a mail, a kill
/// report. A glyph on a raised plate, a mono caption, the title, a mono line, and a chevron when
/// it leads somewhere.
///
/// One step darker than the panel holding the text, with the panel's hairline.
struct HUDLinkCard: View {
    let systemImage: String
    let caption: Text
    let title: Text
    var detail: Text?
    /// `accent` for a line that says what a tap does, `ink-muted` for one that only describes.
    var detailColor: Color = .hudAccent
    var leadsSomewhere = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HUDMetrics.tileRadius, style: .continuous)
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 19))
                .foregroundStyle(Color.hudAccent)
                .frame(width: 44, height: 44)
                .background(Color.hudSurfaceRaised,
                            in: RoundedRectangle(cornerRadius: HUDImagePlate.radius(for: 44), style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HUDImagePlate.radius(for: 44), style: .continuous)
                        .strokeBorder(Color.hudLine, lineWidth: 1)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                caption
                    .font(.hudMicro)
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
                title
                    .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.hudInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let detail {
                    detail
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .textCase(.uppercase)
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if leadsSomewhere {
                HUDChevron()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.hudBg, in: shape)
        .overlay { shape.strokeBorder(Color.hudLine, lineWidth: 1) }
        .contentShape(shape)
    }
}

#Preview("Link card") {
    VStack(spacing: 12) {
        HUDLinkCard(systemImage: "wrench.and.screwdriver",
                    caption: Text(verbatim: "Fitting · Vexor"),
                    title: Text(verbatim: "Vexor — drone ratting"),
                    detail: Text(verbatim: "Open in Fitting Tool"))
        HUDLinkCard(systemImage: "scope",
                    caption: Text(verbatim: "Kill Report"),
                    title: Text(verbatim: "Vexor · Hedda Coldwater"),
                    detail: Text(verbatim: "Frarn · 2026.10.15 21:48"),
                    detailColor: .hudInkMuted)
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudSurface)
}
