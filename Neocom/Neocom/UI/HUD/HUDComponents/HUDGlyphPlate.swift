import SwiftUI

/// A small raised plate with an accent glyph on it: the kind of a row (a wallet category, a
/// journal entry), where there is no picture of the thing itself. Unlike `HUDSymbolPlate`, the
/// glyph is meant to be read, not a placeholder.
struct HUDGlyphPlate: View {
    let systemImage: String
    var size: CGFloat = 36
    var tint: Color = .hudAccent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        shape
            .fill(Color.hudSurfaceRaised)
            .overlay { shape.strokeBorder(Color.hudLine, lineWidth: 1) }
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.46, weight: .regular))
                    .foregroundStyle(tint)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview("Glyph plate") {
    HStack(spacing: 12) {
        HUDGlyphPlate(systemImage: "scope")
        HUDGlyphPlate(systemImage: "tag")
        HUDGlyphPlate(systemImage: "percent", size: 48)
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudSurface)
}
