import LiteRowUI
import MarketKit
import SDEKit
import SwiftUI

/// The price card of the item screen: best sell and best buy in the app's market region, the
/// month's trend, and CCP's average under them. The whole card leads to the market screen.
///
/// A section for `HUDList`, shown only for a type on the market. Picking another region rebuilds
/// the card (`id`); the snapshots stay with `MarketSheet`.
struct MarketPriceCard: View {
    let typeID: TypeID

    @Environment(MarketSheet.self) private var market

    var body: some View {
        let regionID = market.regions.regionID
        MarketPriceCardSection(market: market, typeID: typeID, regionID: regionID)
            .id(regionID)
    }
}

private struct MarketPriceCardSection: View {
    let typeID: TypeID
    let regionID: Int64
    @State private var model: MarketTypeModel

    private static let rowStyle = HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 0)

    init(market: MarketSheet, typeID: TypeID, regionID: Int64) {
        self.typeID = typeID
        self.regionID = regionID
        // Without a pilot there are no distances, so no location is needed.
        _model = State(initialValue: MarketTypeModel(sheet: market, typeID: Int64(typeID.rawValue), regionID: regionID))
    }

    var body: some View {
        let summary = model.summary
        MarketRegionName(regionID: regionID, hubSystemID: nil) { region, _ in
            HUDListSection {
                NavigationLink(value: DatabaseRoute.market(typeID)) {
                    card(summary: summary, region: region)
                        .hudRow(Self.rowStyle)
                }
                .hudRowButton(Self.rowStyle)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Market price in \(region ?? "")"))
                .accessibilityValue(Text("Best sell \(summary.bestSell.map(ISK.price) ?? "—"), best buy \(summary.bestBuy.map(ISK.price) ?? "—")"))
                .accessibilityAddTraits(.isButton)
                .task { await model.loadPrices() }
            }
        }
    }

    private func card(summary: MarketSummary, region: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Market · \(region ?? "—")")
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if summary.sparkline.count >= 2 {
                    HUDSparkline(values: summary.sparkline)
                        .frame(width: 60, height: 18)
                }
                if let change = summary.change {
                    Text(verbatim: String(localized: "\(MarketFormat.signedPercent(change)) 30D"))
                        .tracking(0.5)
                        .foregroundStyle(Color.hudInkBodyMuted)
                        .lineLimit(1)
                }
                HUDChevron()
            }
            .font(.hudMicro)
            .frame(minHeight: 18)
            .padding(.leading, HUDMetrics.gutter)
            .padding(.trailing, 14)
            .padding(.top, 12)

            HStack(spacing: 0) {
                price(Text("Best Sell"), summary.bestSell)
                    .padding(.leading, HUDMetrics.gutter)
                Rectangle().fill(Color.hudLine).frame(width: 1)
                price(Text("Best Buy"), summary.bestBuy)
                    .padding(.leading, 14)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Rectangle().fill(Color.hudLine).frame(height: 1)

            Text(verbatim: "\(String(localized: "EVE Average").uppercased()) \(summary.ccpAverage.map(ISK.price) ?? "—")")
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.vertical, 9)
        }
    }

    private func price(_ label: Text, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label
                .font(.hudMicro)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value.map(ISK.priceFigure) ?? "—")
                    .font(HUDFont.mono(16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.hudInk)
                if value != nil {
                    Text(verbatim: "ISK")
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(Color.hudInkMuted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
