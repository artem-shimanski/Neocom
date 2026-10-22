import SwiftUI

/// The image plate with a glyph on it instead of a picture, for what the image server has no
/// image of: a station seen from the asset list, a structure nobody can name.
///
/// The same plate as `HUDImagePlate` — size, radius, light-theme outline — so it lines up with
/// the icons and renders beside it; the glyph is `image-plate-glyph`, faint against the plate in
/// both themes, a placeholder and not a state.
struct HUDSymbolPlate: View {
    let systemImage: String
    var size: CGFloat = 48

    var body: some View {
        HUDImagePlate(url: nil, size: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .regular))
                    .foregroundStyle(Color.hudImagePlateGlyph)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Symbol plate") {
    HStack(spacing: 12) {
        HUDSymbolPlate(systemImage: "building.2", size: 48)
        HUDSymbolPlate(systemImage: "questionmark", size: 56)
    }
    .padding(.horizontal, HUDMetrics.gutter)
    .padding(.top, 8)
    .background(Color.hudBg.ignoresSafeArea())
}
