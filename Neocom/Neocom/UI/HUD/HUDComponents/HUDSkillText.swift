import SDEKit
import SwiftUI

/// A skill and its level the way the HUD writes it: the name in the display face, the Roman
/// numeral after it in mono.
func hudSkillText(_ name: String, level: Int) -> Text {
    let numeral = Text(verbatim: " " + SkillLevel.roman(level))
        .font(HUDFont.mono(15, weight: .regular, relativeTo: .body))
        .foregroundStyle(Color.hudInkMuted)
    return Text("\(Text(verbatim: name))\(numeral)")
}

#Preview("Skill text") {
    HUDList {
        HUDListSection {
            hudSkillText("Gunnery", level: 1).hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
            hudSkillText("Weapon Upgrades", level: 3).hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
            hudSkillText("Turret Alignment Computer Operation", level: 5).hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
        }
    }
}
