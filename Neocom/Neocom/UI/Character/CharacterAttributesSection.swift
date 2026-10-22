import SDEKit
import SwiftUI
import TrainingKit

/// The five attributes, with the implants that raise them.
///
/// `Pilot` does the adding: `attributes` is the total every training time is computed from,
/// `baseAttributes` is the attribute as the game's character sheet shows it.
struct CharacterAttributesSection: View {
    let pilot: Pilot

    /// The scale of the bars: a little above the highest total a character can reach.
    private static let scale = 32.0

    var body: some View {
        HUDListSection("Attributes") {
            ForEach(CharacterAttribute.displayOrder, id: \.self) { attribute in
                row(attribute, title: attribute.title)
            }
        }
    }

    private func row(_ attribute: CharacterAttribute, title: LocalizedStringKey) -> some View {
        let base = pilot.baseAttributes[attribute]
        let bonus = pilot.implantBonus[attribute]
        return HStack(spacing: 8) {
            Text(title)
                .font(.hudReadout)
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 112, alignment: .leading)
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Color.hudAccent
                        .frame(width: proxy.size.width * min(1, Double(base) / Self.scale))
                    Color.hudAccent.opacity(0.45)
                        .frame(width: proxy.size.width * min(1, Double(bonus) / Self.scale))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.hudSurfaceRaised)
                .clipShape(.capsule)
            }
            .frame(height: 6)
            Text(pilot.attributes[attribute].formatted(.number))
                .font(.hudFigure)
                .frame(minWidth: 28, alignment: .trailing)
            Text(verbatim: bonus == 0 ? "" : "\(base.formatted(.number)) + \(bonus.formatted(.number))")
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .foregroundStyle(Color.hudInkMuted)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(pilot.attributes[attribute].formatted(.number)))
    }
}
