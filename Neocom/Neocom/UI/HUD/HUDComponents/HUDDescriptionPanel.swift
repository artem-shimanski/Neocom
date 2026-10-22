import SwiftUI

/// A panel of running text: an item's or a certificate's description.
struct HUDDescriptionPanel: View {
    let text: AttributedString

    var body: some View {
        HUDPanel {
            Text(text)
                .font(HUDFont.display(15, weight: .regular, relativeTo: .body))
                .lineSpacing(4)
                .foregroundStyle(Color.hudInkBodyMuted)
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

#Preview("Description panel") {
    HUDList {
        Section {
            HUDDescriptionPanel(text: AttributedString(
                "A heavy electron blaster that fires a single high-damage shot at long range. Its capacitor makes it slow to fire, but each hit lands hard."))
                .hudBareRow()
        }
    }
}
