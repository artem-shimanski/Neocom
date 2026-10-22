import SwiftUI

/// The dotted leader between a readout's label and its value. Its bottom sits on the text
/// baseline, the way a dotted underline would.
struct HUDLeader: View {
    var body: some View {
        HorizontalLine()
            .stroke(Color.hudLineLeader, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.5, 3]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private struct HorizontalLine: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

#Preview("Leader") {
    HUDList {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "Label").tracking(1).textCase(.uppercase).foregroundStyle(Color.hudInkMuted)
                HUDLeader().frame(minWidth: 12)
                Text(verbatim: "Value")
            }
            .font(.hudReadout)
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
        }
    }
}
