import SwiftUI

/// The highlight a tapped row gets: `surface-raised` under the content while pressed. It fills
/// the whole label; the row cell (`hudRowCell`) clips it to the card, corners included.
struct HUDRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.hudSurfaceRaised : .clear)
            .foregroundStyle(Color.hudInk)
    }
}

extension ButtonStyle where Self == HUDRowButtonStyle {
    static var hudRow: HUDRowButtonStyle { HUDRowButtonStyle() }
}

extension View {
    /// A `Button` or `NavigationLink` as one row of a `HUDList` card: the `hudRow` button style,
    /// and the card cell (`hudRowCell`) on the button itself, where the List reads it. The label
    /// still carries `hudRow` for its padding and touch height; pass the same `style` here when
    /// the label's is not the default, so the card is cut the same way.
    func hudRowButton(_ style: HUDRowStyle = .default) -> some View {
        self
            .buttonStyle(.hudRow)
            .hudRowCell(style)
    }
}

#Preview("Row button") {
    HUDList {
        Section {
            Button {} label: {
                HStack(spacing: 8) {
                    Text(verbatim: "Open Fitting").font(.hudBody)
                    Spacer()
                    HUDChevron()
                }
                .hudRow()
            }
            .hudRowButton()
        }
    }
}
