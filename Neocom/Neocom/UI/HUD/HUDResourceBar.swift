import SwiftUI

// MARK: - Resource bar

/// The continuous counterpart of `HUDLevelBar`: a hairline capsule showing how much of a budget
/// is spent.
///
/// The bar carries no figure; the row that owns it prints `used / total`. Colour is the only
/// state: `init(used:total:)` turns over budget into `danger`, and the fill stops at the edge.
struct HUDResourceBar: View {
    /// How much of the track to fill, 0…1; out-of-range values are clamped.
    var fraction: Double
    var color: Color = .hudAccent
    var height: CGFloat = 4
    /// Where the fill is going, 0…1: a forecast past `fraction` is drawn after the fill in a
    /// fainter wash. A forecast at or below `fraction` adds nothing.
    var forecast: Double?

    /// How far the fill is let down towards the track; `HUDDamageBlock`'s tracks use the same
    /// value.
    static let fillOpacity: Double = 0.45
    /// The forecast tail, fainter than the fill.
    static let forecastOpacity: Double = 0.2

    var body: some View {
        GeometryReader { proxy in
            let now = min(max(fraction, 0), 1)
            let end = max(now, min(max(forecast ?? 0, 0), 1))
            HStack(spacing: 0) {
                color.opacity(Self.fillOpacity)
                    .frame(width: proxy.size.width * now)
                color.opacity(Self.forecastOpacity)
                    .frame(width: proxy.size.width * (end - now))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hudSurfaceRaised)
            .clipShape(.capsule)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

extension HUDResourceBar {
    /// `used` out of `total`, turning `danger` once the budget is passed. A `total` of zero
    /// leaves the track empty.
    init(used: Double, total: Double, color: Color = .hudAccent, overBudgetColor: Color = .hudDanger,
         height: CGFloat = 4) {
        self.fraction = total > 0 ? used / total : 0
        self.color = used > total ? overBudgetColor : color
        self.height = height
    }
}

#Preview {
    HUDList {
        HUDListSection("Resource Bar") {
            HUDResourceBarPreviewRow("Under budget", bar: HUDResourceBar(used: 420, total: 500))
            HUDResourceBarPreviewRow("Over budget", bar: HUDResourceBar(used: 12_000, total: 11_500))
            HUDResourceBarPreviewRow("No budget at all", bar: HUDResourceBar(used: 0, total: 0))
            HUDResourceBarPreviewRow("Plain fraction", bar: HUDResourceBar(fraction: 0.63, color: .hudDamageThermal))
            HUDResourceBarPreviewRow("With forecast", bar: HUDResourceBar(fraction: 0.3, height: 6, forecast: 0.55))
            HUDResourceBarPreviewRow("Forecast filling up", bar: HUDResourceBar(fraction: 0.86, color: .hudWarn,
                                                                               height: 6, forecast: 1))
        }
    }
}

private struct HUDResourceBarPreviewRow: View {
    let title: LocalizedStringKey
    let bar: HUDResourceBar

    init(_ title: LocalizedStringKey, bar: HUDResourceBar) {
        self.title = title
        self.bar = bar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.hudMicro)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
            bar
        }
        .hudRow()
    }
}
