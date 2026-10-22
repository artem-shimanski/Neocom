import CoreText
import SwiftUI
import UIKit

/// The type of the Neocom HUD design system: Chakra Petch for display text, JetBrains Mono
/// for every number and label, and SF Pro — the system font — for everything the system
/// draws itself.
///
/// Both families ship in the bundle (`Resources/Fonts`, SIL Open Font License) as static
/// faces, one file per weight, and are registered on first use rather than listed in the
/// Info.plist, which this project generates. Each style asks for its face by PostScript name
/// — what `Font.custom` resolves most reliably — and scales with Dynamic Type through
/// `relativeTo:`. A face that failed to register falls back to the system font at the same
/// size and weight, monospaced for the data styles, so the figures still line up.
enum HUDFont {
    static func display(_ size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) -> Font {
        guard let name = faces["ChakraPetch-\(Self.suffix(weight, available: ["Regular", "Medium", "SemiBold", "Bold"]))"] else {
            return .system(size: size, weight: weight)
        }
        return .custom(name, size: size, relativeTo: style)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) -> Font {
        guard let name = faces["JetBrainsMono-\(Self.suffix(weight, available: ["Regular", "Medium", "SemiBold"]))"] else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(name, size: size, relativeTo: style)
    }

    /// The bundled face closest to `weight`, by its file's suffix.
    private static func suffix(_ weight: Font.Weight, available: [String]) -> String {
        let wanted: String = switch weight {
        case .bold, .heavy, .black: "Bold"
        case .semibold: "SemiBold"
        case .medium: "Medium"
        default: "Regular"
        }
        return available.contains(wanted) ? wanted : available.last ?? "Regular"
    }

    /// Bundled font file name (without extension) → the PostScript name it registered under.
    ///
    /// Registered once, the first time any style is asked for. The name is read back from the
    /// font itself rather than assumed from the file name.
    private static let faces: [String: String] = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        var faces: [String: String] = [:]
        for url in urls {
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let name = descriptors.first.flatMap({ CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String })
            else { continue }
            var error: Unmanaged<CFError>?
            // Already registered — by a previous call in a preview, say — is as good as done.
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) || UIFont(name: name, size: 12) != nil {
                faces[url.deletingPathExtension().lastPathComponent] = name
            }
        }
        return faces
    }()
}

/// The type styles of the design system, by the names its tokens give them.
extension Font {
    // Display

    /// Pilot name on the Character Sheet, uppercase.
    static var hudPilotName: Font { HUDFont.display(26, weight: .bold, relativeTo: .title2) }
    /// Pilot name on the home card.
    static var hudCardTitle: Font { HUDFont.display(21, weight: .semibold, relativeTo: .title3) }
    /// Navigation tile and list-row titles, sentence case.
    static var hudTileTitle: Font { HUDFont.display(16, weight: .semibold, relativeTo: .headline) }
    /// Proper names and sentences inside panels.
    static var hudBody: Font { HUDFont.display(15, weight: .medium, relativeTo: .body) }

    /// Action rows and form rows inside a sheet: the system face at the body size.
    static var hudSheetBody: Font { .body }

    // Data

    /// The one key figure of a panel.
    static var hudFigureXL: Font { HUDFont.mono(28, weight: .semibold, relativeTo: .title) }
    /// Values in a stat strip.
    static var hudFigure: Font { HUDFont.mono(15, weight: .semibold, relativeTo: .body) }
    /// Readout rows: labels and values.
    static var hudReadout: Font { HUDFont.mono(13, weight: .regular, relativeTo: .subheadline) }
    /// Corporation line, system and region, times.
    static var hudCaption: Font { HUDFont.mono(12, weight: .regular, relativeTo: .caption) }
    /// Section headers and status chips. Uppercase, 2 pt tracking.
    static var hudLabel: Font { HUDFont.mono(11, weight: .medium, relativeTo: .caption) }
    /// Panel headers and stat labels. Uppercase, 2 pt tracking.
    static var hudMicro: Font { HUDFont.mono(10, weight: .medium, relativeTo: .caption2) }
}
