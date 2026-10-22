import MarketKit
import SwiftUI

/// The price history card: the selected day's figures, the chart of the average inside its
/// low–high band with the volume under it, and the span — a month, three months, a year. A
/// year is drawn in weeks: 365 bars are too thin to tap one.
struct MarketHistorySection: View {
    let model: MarketTypeModel

    @State private var span: Span = .month
    @State private var selection: Int?

    enum Span: Int, CaseIterable, Identifiable {
        case month = 30
        case quarter = 90
        case year = 365

        var id: Int { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .month: "1M"
            case .quarter: "3M"
            case .year: "1Y"
            }
        }

        var caption: LocalizedStringKey {
            switch self {
            case .month: "30 days"
            case .quarter: "90 days"
            case .year: "12 months"
            }
        }

        var bucket: Int { self == .year ? 7 : 1 }
    }

    var body: some View {
        let periods = self.periods
        HUDListSection {
            if periods.isEmpty {
                placeholder
                    .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))
            } else {
                let index = min(selection ?? periods.count - 1, periods.count - 1)
                dayHeader(periods[index])
                    .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 12))
                chart(periods, selected: index)
                    .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))
            }
        } header: {
            HUDSectionHeader(Text("Price History")) {
                Text(span.caption)
            }
        }
        .onChange(of: span) { selection = nil }
    }

    private var periods: [MarketHistoryDay] {
        let days = model.history(lastDays: span.rawValue)
        return span.bucket > 1 ? MarketMath.aggregate(days, bucketDays: span.bucket) : days
    }

    @ViewBuilder private var placeholder: some View {
        if model.history.value == nil {
            if case let .failed(error) = model.history.state {
                Text(error.localizedDescription)
                    .font(.hudCaption)
                    .foregroundStyle(Color.hudInkMuted)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("No trades in this region over the span.")
                    .font(.hudCaption)
                    .foregroundStyle(Color.hudInkMuted)
                spanPicker
            }
        }
    }

    // MARK: Selected day

    private func dayHeader(_ day: MarketHistoryDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: dateTitle(day))
                    .font(HUDFont.display(17, weight: .bold, relativeTo: .headline))
                    .tracking(0.5)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: ISK.price(day.average))
                    .font(HUDFont.mono(20, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(Color.hudAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
            HStack(alignment: .top, spacing: 8) {
                figure(Text("Low – High"), "\(ISK.compact(day.lowest)) – \(ISK.compact(day.highest))")
                figure(Text("Volume"), MarketFormat.quantity(day.volume))
                figure(Text("Orders"), MarketFormat.quantity(day.orderCount))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// `2026.10.15`, or the week for a year's bar: `2026.10.05 – 10.11`.
    private func dateTitle(_ day: MarketHistoryDay) -> String {
        guard span.bucket > 1 else { return EVETime.date(day.date) }
        let last = day.date.addingTimeInterval(Double(span.bucket - 1) * 86_400)
        return "\(EVETime.date(day.date)) – \(EVETime.monthDay(last))"
    }

    private func figure(_ label: Text, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label
                .font(.hudMicro)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
            Text(verbatim: value)
                .font(HUDFont.mono(13, weight: .regular, relativeTo: .subheadline))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Chart

    private func chart(_ periods: [MarketHistoryDay], selected: Int) -> some View {
        let points = periods.enumerated().map { index, day in
            HUDBandChart.Point(id: index, value: day.average, low: day.lowest, high: day.highest,
                               bar: Double(day.volume),
                               accessibilityLabel: Text("\(EVETime.date(day.date)), volume \(MarketFormat.quantity(day.volume))"))
        }
        return VStack(alignment: .leading, spacing: 6) {
            HUDBandChart(points: points,
                         selection: Binding(get: { selected }, set: { selection = $0 }),
                         valueLabel: ISK.compact,
                         barLabel: { MarketFormat.quantity(Int64($0)) },
                         accessibilityLabel: Text("Daily average price with low to high band"))
            HStack {
                Text(verbatim: periods.first.map { EVETime.monthDay($0.date) } ?? "")
                Spacer()
                Text(verbatim: periods.last.map { EVETime.monthDay($0.date) } ?? "")
            }
            .font(HUDFont.mono(10, weight: .regular, relativeTo: .caption2))
            .foregroundStyle(Color.hudInkMuted)
            .padding(.leading, HUDBandChart.labelWidth + HUDBandChart.labelSpacing)
            .accessibilityHidden(true)

            spanPicker
                .padding(.top, 8)
            HUDChartLegend(items: [
                .init(id: 0, swatch: .line(.hudAccent), text: Text("Average")),
                .init(id: 1, swatch: .block(.hudAccent.opacity(0.16)), text: Text("Low – High")),
                .init(id: 2, swatch: .block(.hudAccent.opacity(0.35)), text: Text("Volume")),
            ])
            .padding(.top, 4)
        }
    }

    private var spanPicker: some View {
        Picker("Span", selection: $span) {
            ForEach(Span.allCases) { span in
                Text(span.title).tag(span)
            }
        }
        .pickerStyle(.segmented)
    }
}
