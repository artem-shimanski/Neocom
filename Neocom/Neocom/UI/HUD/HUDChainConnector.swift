import SwiftUI

/// The step between two rows of a production flow: a stem, the flow crossing it as pills
/// (`29 700 P0/h`), and an arrow down. A flow going back up is a separate pill with a U-turn glyph.
struct HUDChainConnector: View {
    /// What flows down to the rows below.
    var flows: [Text]
    /// What flows back up to a row above.
    var returns: [Text] = []

    var body: some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(Color.hudLineLeader)
                .frame(width: 2, height: 10)
            ForEach(flows.indices, id: \.self) { index in
                pill(flows[index], systemImage: nil)
            }
            ForEach(returns.indices, id: \.self) { index in
                pill(returns[index], systemImage: "arrow.turn.left.up")
            }
            if !flows.isEmpty {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.hudInkFaint)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func pill(_ text: Text, systemImage: String?) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }
            text
                .font(HUDFont.mono(10, weight: .regular, relativeTo: .caption2))
                .tracking(0.5)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.hudInkBodyMuted)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .overlay(Capsule().strokeBorder(Color.hudLine, lineWidth: 1))
    }
}

#Preview("Chain connector") {
    HUDList {
        Section {
            VStack(spacing: 0) {
                HUDChainConnector(flows: [Text(verbatim: "29 700 P0/h")])
                HUDChainConnector(flows: [Text(verbatim: "28 200 P0/h"), Text(verbatim: "60 P1/h")])
                HUDChainConnector(flows: [], returns: [Text(verbatim: "188 P1/h to Storage Facility")])
            }
            .hudBareRow()
        }
    }
}
