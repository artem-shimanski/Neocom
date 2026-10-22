import SwiftUI

/// A square-ish tile linking to a screen: icon and optional status on top, title and optional
/// subtitle at the bottom.
struct HUDNavTile<Status: View>: View {
    let systemImage: String
    let title: Text
    var subtitle: Text?
    var tone: HUDTone = .normal
    @ViewBuilder var status: Status

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HUDMetrics.tileRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.hudAccent)
                    .accessibilityHidden(true)
                Spacer(minLength: 4)
                status
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.hudTileTitle)
                    .tracking(0.3)
                    .foregroundStyle(Color.hudInk)
                if let subtitle {
                    subtitle
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Color.hudSurface, in: shape)
        .overlay {
            shape.strokeBorder(tone.border, lineWidth: 1)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

extension HUDNavTile where Status == EmptyView {
    init(systemImage: String, title: Text, subtitle: Text? = nil) {
        self.init(systemImage: systemImage, title: title, subtitle: subtitle, status: { EmptyView() })
    }
}

#Preview("Nav tile") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HUDMetrics.headerSpacing) {
        HUDNavTile(systemImage: "shield.lefthalf.filled", title: Text("Fittings"), subtitle: Text(verbatim: "12 fits"))
        HUDNavTile(systemImage: "chart.bar.fill", title: Text("Stats"))
    }
    .padding(.horizontal, HUDMetrics.gutter)
    .background(Color.hudBg.ignoresSafeArea())
}
