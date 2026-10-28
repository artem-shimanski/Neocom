import BusinessKit
import SDEKit
import SwiftUI

/// One type's trades of 30 days: what was sold and bought, at what averages, the estimated
/// profit on the units both bought and sold, and each trade.
struct WalletMarketItemView: View {
    let model: WalletModel
    let typeID: Int64

    var body: some View {
        WalletScreen(model: model) { _ in
            WalletItemDetail(model: model, typeID: typeID)
        }
        .navigationTitle(model.typeName(typeID))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WalletItemDetail: View {
    let model: WalletModel
    let typeID: Int64

    private var sdeTypeID: TypeID { TypeID(rawValue: UInt32(clamping: typeID)) }

    var body: some View {
        if let item = model.marketSummary.items.first(where: { $0.typeID == typeID }) {
            let trades = model.transactions.filter { $0.typeID == typeID }
            HUDList {
                Section { header(item).hudBareRow() }
                result(item)
                HUDListSection(trades, row: { trade in tradeRow(trade) }, header: {
                    HUDSectionHeader(Text("Trades · \(trades.count)"))
                })
                links
                Section {
                    HUDFootnote("Profit is an estimate: units sold and bought inside these 30 days are matched at their average prices, less the sales tax on those sales. What was bought before the window or is still in the hangar is not counted.")
                        .hudBareRow()
                }
            }
        } else {
            HUDList {
                Section {
                    HUDEmptyPanel(title: Text("No Trades"),
                                  message: Text("This item was not traded from this wallet in the last 30 days."))
                        .hudBareRow()
                }
            }
        }
    }

    private func header(_ item: WalletMarketItem) -> some View {
        HUDPanel {
            NavigationLink(value: DatabaseRoute.type(sdeTypeID)) {
                HStack(spacing: 12) {
                    HUDItemIcon(typeID: sdeTypeID, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: model.typeName(typeID))
                            .font(HUDFont.display(18, weight: .bold, relativeTo: .headline))
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .lineLimit(2)
                        if let group = model.types[typeID]?.group {
                            Text(verbatim: group)
                                .font(.hudMicro)
                                .tracking(1)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.hudInkMuted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HUDChevron()
                }
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HUDPanelRule()
            HUDStatStrip(items: [
                .init(id: 0, label: Text("Sold"), value: Text(verbatim: MarketFormat.quantity(item.soldQuantity))),
                .init(id: 1, label: Text("Bought"), value: Text(verbatim: MarketFormat.quantity(item.boughtQuantity))),
                .init(id: 2, label: Text("Spread"), value: Text(verbatim: item.spread.map(MarketFormat.signedPercent) ?? "—")),
            ])
        }
        .foregroundStyle(Color.hudInk)
    }

    private func result(_ item: WalletMarketItem) -> some View {
        HUDListSection(Text("Result · 30 Days")) {
            if let average = item.averageSell {
                HUDReadoutRow("Avg Sell", value: ISK.price(average))
            }
            if let average = item.averageBuy {
                HUDReadoutRow("Avg Buy", value: ISK.price(average))
            }
            if item.soldQuantity > 0 {
                HUDReadoutRow("Matched", value: String(localized: "\(MarketFormat.quantity(item.matchedUnits)) of \(MarketFormat.quantity(item.soldQuantity)) sold"))
            }
            if item.salesTax > 0 {
                HUDReadoutRow("Sales Tax", value: ISK.price(item.salesTax))
            }
            if let profit = item.estimatedProfit {
                HUDReadoutRow("Est. Profit") {
                    Text(verbatim: "\(WalletText.signed(profit)) ISK")
                        .fontWeight(.semibold)
                        .foregroundStyle(WalletText.color(profit))
                }
            } else {
                HUDReadoutRow("Net Flow") {
                    Text(verbatim: "\(WalletText.signed(item.netFlow)) ISK")
                        .foregroundStyle(WalletText.color(item.netFlow))
                }
            }
        }
    }

    @ViewBuilder
    private func tradeRow(_ trade: WalletTransaction) -> some View {
        if let entry = model.ledger.entry(for: trade) {
            NavigationLink(value: WalletRoute(division: model.source.division, page: .entry(entry.id))) {
                WalletTradeRow(model: model, trade: trade)
            }
            .hudRowButton(WalletTradeRow.rowStyle)
        } else {
            WalletTradeRow(model: model, trade: trade)
        }
    }

    private var links: some View {
        HUDListSection {
            NavigationLink(value: DatabaseRoute.market(sdeTypeID)) {
                HUDLinkRowLabel(systemImage: "chart.line.uptrend.xyaxis",
                                title: Text("Market · \(model.typeName(typeID))"))
            }
            .hudRowButton()
            if let orders = ordersSection {
                NavigationLink(value: orders) {
                    HUDLinkRowLabel(systemImage: orders.systemImage, title: Text(orders.title))
                }
                .hudRowButton()
            }
        }
    }

    /// The pilot's own orders, or the corporation's where its roles allow reading them.
    private var ordersSection: MainMenuSection? {
        guard model.isCorporation else { return .marketOrders }
        return model.corporation?.access.orders == true ? .corporationOrders : nil
    }
}
