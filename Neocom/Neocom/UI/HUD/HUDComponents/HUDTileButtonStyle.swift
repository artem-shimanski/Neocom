import SwiftUI

/// The pressed and disabled states of a tile: a slight dim when pressed, a stronger one when
/// disabled — the tile already looks like a control.
struct HUDTileButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == HUDTileButtonStyle {
    static var hudTile: HUDTileButtonStyle { HUDTileButtonStyle() }
}

#Preview("Tile button") {
    Button {} label: {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "wrench.fill")
                .font(.title3)
                .foregroundStyle(Color.hudAccent)
            Spacer(minLength: 0)
            Text(verbatim: "Editor").font(.hudTileTitle).tracking(0.3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Color.hudSurface, in: RoundedRectangle(cornerRadius: HUDMetrics.tileRadius, style: .continuous))
    }
    .buttonStyle(.hudTile)
    .padding(.horizontal, HUDMetrics.gutter)
    .background(Color.hudBg.ignoresSafeArea())
}
