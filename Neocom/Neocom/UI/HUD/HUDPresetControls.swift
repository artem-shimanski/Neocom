import SwiftUI

/// A small key: a mono word, accent when it is the current state of what it sets.
///
/// `title` is the key's shorthand (`ALL 0`, a Roman numeral, `CLEAR`); `accessibilityLabel`
/// spells it out where the shorthand is not a phrase.
struct HUDPresetKey: View {
    let title: Text
    let isSelected: Bool
    /// Spoken instead of `title`, for a key whose face is an abbreviation.
    var accessibilityLabel: Text?
    /// A key in a row of six is 40 pt on a 12 pt radius; a single key beside the pilot card is
    /// 56 pt on the tile radius.
    var minHeight: CGFloat = 40
    var cornerRadius: CGFloat = 12
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Button(action: action) {
            title
                .font(HUDFont.mono(12, weight: .semibold, relativeTo: .caption))
                // Upper-cased like every mono label of the design.
                .textCase(.uppercase)
                .foregroundStyle(isSelected ? Color.hudAccent : Color.hudInkBodyMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(isSelected ? Color.hudAccent.opacity(0.14) : Color.hudSurface, in: shape)
                .overlay {
                    shape.strokeBorder(isSelected ? Color.hudAccent.opacity(0.4) : Color.hudLine, lineWidth: 1)
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The pilot as a preset: portrait, name, and what tapping does. The caption is the caller's
/// wording of what the preset copies.
struct HUDPilotPresetCard: View {
    let account: Account?
    /// The mono line under the name.
    let caption: Text
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HUDMetrics.tileRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                if let account {
                    HUDImagePlate(url: account.portraitURL, size: 34, radius: 17)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: account?.characterName ?? String(localized: "Pilot"))
                        .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Color.hudInk)
                        .lineLimit(1)
                    caption
                        .font(.hudLabel)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                // Always laid out so the card's width does not change with the choice, or a
                // `HUDPilotCarousel` would switch between filling and scrolling on a tap.
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.hudAccent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isSelected ? Color.hudAccent.opacity(0.10) : Color.hudSurface, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? Color.hudAccent.opacity(0.4) : Color.hudLine, lineWidth: 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Preset controls") {
    VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 6) {
            ForEach(0...5, id: \.self) { level in
                HUDPresetKey(title: Text(verbatim: level == 0 ? "ALL 0" : SkillLevel.roman(level)),
                             isSelected: level == 5,
                             accessibilityLabel: Text("All \(SkillLevel.roman(level))")) {}
            }
        }
        HStack(spacing: 6) {
            HUDPilotPresetCard(account: nil, caption: Text("6 Implants · Copy"), isSelected: true) {}
            HUDPresetKey(title: Text("Clear"), isSelected: false,
                         minHeight: 56, cornerRadius: HUDMetrics.tileRadius) {}
                .frame(width: 96)
        }
    }
    .padding()
    .background(Color.hudBg)
}
