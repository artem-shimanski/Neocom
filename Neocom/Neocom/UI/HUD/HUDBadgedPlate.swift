import SwiftUI

/// An image plate with a small second one on its bottom-trailing corner, ringed in the surface
/// colour. Without a `badgeURL` it is the plain plate.
struct HUDBadgedPlate: View {
    let url: URL?
    var size: CGFloat = 44
    var badgeURL: URL?
    var badgeSize: CGFloat = 22
    /// Ring colour around the badge; the colour of the surface under the plate.
    var ringColor: Color = .hudSurface

    private static let ring: CGFloat = 2
    /// How far the badge hangs past the plate's edge.
    private static let overhang: CGFloat = 4

    var body: some View {
        HUDImagePlate(url: url, size: size)
            .overlay(alignment: .bottomTrailing) {
                if let badgeURL {
                    let radius: CGFloat = 6
                    HUDImagePlate(url: badgeURL, size: badgeSize, radius: radius)
                        .padding(Self.ring)
                        .background(ringColor,
                                    in: RoundedRectangle(cornerRadius: radius + Self.ring, style: .continuous))
                        .offset(x: Self.overhang + Self.ring, y: Self.overhang + Self.ring)
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview("Badged plate") {
    HStack(spacing: 20) {
        HUDBadgedPlate(url: EVEImage.icon(typeID: 11_387, size: 128),
                       badgeURL: EVEImage.icon(typeID: 3_074, size: 64))
        HUDBadgedPlate(url: EVEImage.icon(typeID: 11_387, size: 128))
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudSurface)
}
