import SwiftUI

/// A panel's header strip: a micro label on the left, optional status on the right, a `line`
/// rule under it.
struct HUDPanelHeader<Trailing: View>: View {
    let title: Text
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            title
                .font(.hudMicro)
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, HUDMetrics.gutter)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hudLine).frame(height: 1)
        }
    }
}

extension HUDPanelHeader where Trailing == EmptyView {
    init(title: Text) {
        self.title = title
        self.trailing = EmptyView()
    }
}

#Preview("Panel header") {
    HUDList {
        Section {
            HUDPanel {
                HUDPanelHeader(title: Text("Modules")) {
                    Text(verbatim: "4/8").font(.hudMicro)
                }
                Text(verbatim: "First row under the strip").hudRow()
                Text(verbatim: "Second row").hudRow()
            }
            .hudBareRow()
        }
    }
}
