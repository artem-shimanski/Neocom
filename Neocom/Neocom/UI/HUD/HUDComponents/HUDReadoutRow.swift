import SwiftUI

/// Label, dotted leader, value: the HUD way to list facts.
///
/// A card of readouts stands 4pt further off its border than its rows are apart: the first and
/// the last readout of a card take `cardEdgePadding` on that side (`HUDRowStyle.readout`).
struct HUDReadoutRow<Value: View>: View {
    let label: Text
    @ViewBuilder var value: Value

    init(_ label: Text, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    init(_ label: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.init(Text(label), value: value)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            label
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                // A long value must not squeeze the label to a letter a line: the label keeps
                // a floor, and the value wraps in what is left.
                .frame(minWidth: 110, alignment: .leading)
                .layoutPriority(1)
            HUDLeader()
                .frame(minWidth: 12)
            value
                .multilineTextAlignment(.trailing)
                .layoutPriority(2)
        }
        .font(.hudReadout)
        .hudRow(.readout)
    }
}

extension HUDReadoutRow where Value == Text {
    init(_ label: LocalizedStringKey, value: String) {
        self.init(Text(label)) { Text(value) }
    }

    init(_ label: Text, value: String) {
        self.init(label) { Text(value) }
    }
}

#Preview("Readout row") {
    HUDList {
        HUDListSection("Readouts") {
            HUDReadoutRow(Text("Mass"), value: "12 480 m³")
            HUDReadoutRow("Volume", value: "50 m³")
            HUDReadoutRow("Capacity") {
                Text(verbatim: "41%").foregroundStyle(Color.hudOk)
            }
        }
    }
}
