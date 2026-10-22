import SwiftUI

/// Any game image — an icon, a portrait, a logo — on its plate.
struct HUDImagePlate: View {
    let url: URL?
    var size: CGFloat
    var radius: CGFloat?
    /// The `accent` frame of a pilot portrait.
    var framed = false
    /// What to draw instead when `url` answers with nothing: a ship the image server has no render
    /// for falls back to its icon. `nil` leaves the bare plate.
    var fallbackURL: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            case .failure:
                // A load that failed, not a missing `url`: with no `url` the phase is `.empty`.
                AsyncImage(url: fallbackURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            default:
                Color.clear
            }
        }
        .hudImagePlate(size: size, radius: radius, framed: framed)
    }

    /// Concentric with what the plate sits in: thumbnails step down from the panel's 20.
    static func radius(for size: CGFloat) -> CGFloat {
        switch size {
        case ..<30: 7
        case ..<36: 8
        case ..<60: 10
        case ..<100: 14
        default: 20
        }
    }
}

extension View {
    /// The plate itself, around any image: shared by `HUDImagePlate` and `HUDIconPlate`, so an
    /// icon from the image server and one from the static data sit on the same thing.
    func hudImagePlate(size: CGFloat, radius: CGFloat? = nil, framed: Bool = false) -> some View {
        modifier(HUDImagePlateChrome(size: size, radius: radius, framed: framed))
    }
}

private struct HUDImagePlateChrome: ViewModifier {
    let size: CGFloat
    let radius: CGFloat?
    let framed: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? HUDImagePlate.radius(for: size),
                                     style: .continuous)
        content
            .frame(width: size, height: size)
            .background(Color.hudImagePlate)
            .clipShape(shape)
            .overlay {
                if framed {
                    shape.strokeBorder(Color.hudAccent, lineWidth: 1)
                } else if colorScheme == .light {
                    shape.strokeBorder(Color.hudLine, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}
