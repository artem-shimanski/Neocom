import SwiftUI

/// The small crosshair at a row's trailing edge that says the row is aimed at a ship of the
/// fleet. Not a control: the choice is made in the item's sheet, and the row's own tap still
/// opens that sheet. Draw it only when there is a target.
struct HUDTargetMark: View {
    /// The target ship's name, for VoiceOver.
    let shipName: String

    var body: some View {
        Image(systemName: "scope")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.hudOk)
            .frame(width: 20, height: 20)
            .accessibilityElement()
            .accessibilityLabel(Text("Target: \(shipName)"))
    }
}

#Preview("Target mark") {
    HStack(spacing: 8) {
        Text(verbatim: "Medium Remote Armor Repairer II").font(.hudBody)
        Spacer()
        HUDTargetMark(shipName: "Vexor — drone ratting")
    }
    .hudRow()
    .background(Color.hudSurface)
    .padding()
    .background(Color.hudBg)
}
