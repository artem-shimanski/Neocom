import SwiftUI
import WidgetKit

/// A person or an organisation by their initials, on the raised plate: a mail's sender in the
/// inbox and on the message. With a `url` the game's image covers the initials once it has
/// loaded; while it loads, and when it fails, the initials stay.
///
/// The plate is the `HUDImagePlate` size and radius, so it lines up with icons and portraits
/// in a list that mixes them.
///
/// A widget cannot wait for `AsyncImage`: it passes the portrait it has on disk as `image`,
/// drawn at once. Its colours follow the widget's rendering mode (`HUDInk`).
struct HUDInitialsAvatar: View {
    let name: String
    var size: CGFloat = 36
    /// A portrait or a logo from the image server; `nil` leaves the initials alone.
    var url: URL?
    /// An image already at hand, over the initials; takes the place of `url`.
    var image: Image?

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HUDImagePlate.radius(for: size), style: .continuous)
        let ink = HUDInk(renderingMode)
        Text(verbatim: Self.initials(of: name))
            .font(HUDFont.display(size * 0.36, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(ink.bodyMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(ink.surfaceRaised, in: shape)
            .overlay {
                if let image {
                    image
                        .resizable()
                        .widgetAccentedRenderingMode(.desaturated)
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(shape)
                } else if let url {
                    // Only a loaded image is drawn: the phases before it and a failure show the
                    // initials underneath.
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: size, height: size)
                    .clipShape(shape)
                }
            }
            .overlay { shape.strokeBorder(ink.line, lineWidth: 1) }
            .accessibilityHidden(true)
    }

    /// `MQ` for `Mira Quillfeather`, `R` for `Rens`, `?` for nothing: the first letter of the
    /// first two words that start with one. Brackets and punctuation (`[Corp]`) are skipped.
    static func initials(of name: String) -> String {
        let letters = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .compactMap { word in word.first(where: { $0.isLetter || $0.isNumber }) }
            .prefix(2)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
