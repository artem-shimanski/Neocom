import SwiftUI
import UIKit

/// The tier of an item as a small outlined label (`T2`, `FACTION`, `OFFICER`): mono caps in the
/// tier's colour, with a border of the same colour at reduced strength.
///
/// The colour is the meta group's colour from the SDE (`TypeListRow.metaGroupColor`). A meta
/// group or caller with no colour gets the muted ink.
struct HUDMetaBadge: View {
    let text: Text
    /// The meta group's colour, before it is adapted to the surface.
    var color: Color?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tint = color.map { $0.legible(on: colorScheme) } ?? .hudInkMuted
        text
            .font(.hudMicro)
            .tracking(1)
            .textCase(.uppercase)
            .lineLimit(1)
            // Shrinks before taking the title's room (`PickerTypeRow` holds the title's floor).
            .minimumScaleFactor(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(tint.opacity(0.4), lineWidth: 1)
            }
    }
}

private extension Color {
    /// The same hue moved to where it reads on the panel. CCP's meta colours are too dark on
    /// the dark panel and the gold too pale on the light one, so brightness is raised to a
    /// floor or capped; hue is never touched.
    func legible(on scheme: ColorScheme) -> Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return scheme == .dark
            ? Color(hue: hue, saturation: min(saturation, 0.65), brightness: max(brightness, 0.92))
            : Color(hue: hue, saturation: saturation, brightness: min(brightness, 0.62))
    }
}

#Preview {
    HUDMetaBadgePreview()
}

#Preview("Dark") {
    HUDMetaBadgePreview()
        .preferredColorScheme(.dark)
}

private struct HUDMetaBadgePreview: View {
    var body: some View {
        HUDList {
            HUDListSection("Meta Badge") {
                HStack(spacing: 8) {
                    HUDMetaBadge(text: Text(verbatim: "T1"), color: Color(red: 0.78, green: 0.67, blue: 0.04))
                    HUDMetaBadge(text: Text(verbatim: "T2"), color: Color(red: 0.62, green: 0.38, blue: 0.004))
                    HUDMetaBadge(text: Text(verbatim: "Storyline"), color: Color(red: 0.27, green: 0.43, blue: 0.12))
                }
                .hudRow()
                HStack(spacing: 8) {
                    HUDMetaBadge(text: Text(verbatim: "Faction"), color: Color(red: 0.07, green: 0.28, blue: 0.05))
                    HUDMetaBadge(text: Text(verbatim: "Officer"), color: Color(red: 0.2, green: 0.05, blue: 0.45))
                    HUDMetaBadge(text: Text(verbatim: "Deadspace"), color: Color(red: 0.16, green: 0.28, blue: 0.55))
                }
                .hudRow()
                HStack(spacing: 8) {
                    HUDMetaBadge(text: Text(verbatim: "No colour"), color: nil)
                }
                .hudRow()
            }
        }
    }
}
