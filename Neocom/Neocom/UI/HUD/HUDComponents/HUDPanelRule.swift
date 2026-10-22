import SwiftUI

/// A full-width `line` rule between two blocks of one `HUDPanel`. Between two rows of a card
/// the row divider does this job.
struct HUDPanelRule: View {
    var body: some View {
        Rectangle().fill(Color.hudLine).frame(height: 1)
    }
}

#Preview("Panel rule") {
    HUDList {
        Section {
            HUDPanel {
                Text(verbatim: "Above the rule").padding(HUDMetrics.gutter)
                HUDPanelRule()
                Text(verbatim: "Below the rule").padding(HUDMetrics.gutter)
            }
            .hudBareRow()
        }
    }
}
