import SwiftUI

/// Where a value sits in a range around a reference: a track from the low bound to the high one,
/// a tick at the reference, and the stretch between reference and value filled in `tint`.
/// The bounds can be written under the ends. Used for a mutaplasmid roll; the caller picks the
/// tint.
struct HUDRollBar: View {
    let range: ClosedRange<Double>
    let reference: Double
    let value: Double
    var tint: Color = .hudAccent
    var lowerLabel: Text?
    var upperLabel: Text?

    private static let height: CGFloat = 8

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let tick = position(of: reference)
                let mark = position(of: value)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.hudSurfaceRaised)
                        .strokeBorder(Color.hudLine, lineWidth: 1)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint)
                        .frame(width: width * abs(mark - tick))
                        .offset(x: width * min(mark, tick))
                    Rectangle()
                        .fill(Color.hudInk)
                        .frame(width: 2, height: Self.height + 8)
                        .offset(x: width * tick - 1)
                }
            }
            .frame(height: Self.height)
            .accessibilityHidden(true)
            if lowerLabel != nil || upperLabel != nil {
                HStack {
                    lowerLabel
                    Spacer(minLength: 8)
                    upperLabel
                }
                .font(.hudMicro)
                .tracking(1)
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
            }
        }
    }

    /// 0…1 along the track; the middle for a range of no width.
    private func position(of x: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0.5 }
        return CGFloat(min(1, max(0, (x - range.lowerBound) / span)))
    }
}

#Preview("Roll bar") {
    VStack(spacing: 24) {
        HUDRollBar(range: 331.2...423.2, reference: 368, value: 405, tint: .hudOk,
                   lowerLabel: Text(verbatim: "331.2"), upperLabel: Text(verbatim: "423.2"))
        HUDRollBar(range: 23.8...36.4, reference: 28, value: 25.2, tint: .hudOk)
        HUDRollBar(range: 117.3...179.4, reference: 138, value: 151.8, tint: .hudDanger,
                   lowerLabel: Text(verbatim: "117.3"), upperLabel: Text(verbatim: "179.4"))
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudSurface)
}
