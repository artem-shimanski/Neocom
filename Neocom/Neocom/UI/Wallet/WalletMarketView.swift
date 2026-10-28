import BusinessKit
import SDEKit
import SwiftUI

/// The wallet's market trades of 30 days: what was sold and bought, by item or one by one.
struct WalletMarketView: View {
    let model: WalletModel

    var body: some View {
        WalletScreen(model: model) { now in
            WalletMarketList(model: model, now: now)
        }
        .navigationTitle("Market Transactions")
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(Text(verbatim: model.title))
    }
}

private enum WalletMarketTab: Hashable {
    case items
    case trades
}

private struct WalletMarketList: View {
    let model: WalletModel
    let now: Date

    @State private var tab: WalletMarketTab = .items

    var body: some View {
        let snapshot = model.source.transactions
        if snapshot.value == nil {
            HUDList {
                Section {
                    if let error = snapshot.state.error {
                        HUDEmptyPanel(title: Text("Transactions Unavailable"), message: Text(error.localizedDescription)) {
                            Button("Retry") { Task { await model.source.refresh() } }
                                .hudProminentButton()
                        }
                        .hudBareRow()
                    } else {
                        ProgressView()
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .hudBareRow()
                    }
                }
            }
        } else {
            loaded
        }
    }

    private var loaded: some View {
        let summary = model.marketSummary
        return HUDList {
            Section {
                VStack(alignment: .leading, spacing: HUDMetrics.headerSpacing) {
                    HUDPanel {
                        HUDStatStrip(items: [
                            .init(id: 0, label: Text("Sold"), value: Text(verbatim: WalletText.signed(summary.soldValue)),
                                  color: WalletText.color(summary.soldValue)),
                            .init(id: 1, label: Text("Bought"), value: Text(verbatim: WalletText.signed(-summary.boughtValue))),
                            .init(id: 2, label: Text("Tax & Fees"), value: Text(verbatim: WalletText.signed(-summary.fees))),
                        ])
                    }
                    HUDFreshnessChip(model.source.transactions, now: now)
                }
                .hudLeadingBlock()
            }

            Section {
                Picker("View", selection: $tab) {
                    Text("By Item").tag(WalletMarketTab.items)
                    Text(verbatim: "\(String(localized: "All Trades")) · \(summary.tradeCount)").tag(WalletMarketTab.trades)
                }
                .pickerStyle(.segmented)
                .hudBareRow()
            }

            if summary.items.isEmpty {
                Section {
                    HUDEmptyPanel(title: Text("No Trades"),
                                  message: Text("Market trades of the last 30 days show here: what was sold and bought, at what price and with whom."))
                        .hudBareRow()
                }
            } else {
                switch tab {
                case .items:
                    HUDListSection(summary.items, row: { item in
                        NavigationLink(value: WalletRoute(division: model.source.division, page: .item(item.typeID))) {
                            WalletItemRow(model: model, item: item)
                        }
                        .hudRowButton(WalletItemRow.rowStyle)
                        .contextMenu {
                            HUDTypeCopyButtons(typeID: item.typeID, name: model.typeName(item.typeID))
                        }
                    }, header: {
                        HUDSectionHeader(Text("Items · \(summary.items.count)")) {
                            Text("By turnover")
                        }
                    })
                case .trades:
                    ForEach(model.tradeDays) { day in
                        HUDListSection(day.trades, row: { trade in
                            NavigationLink(value: WalletRoute(division: model.source.division, page: .item(trade.typeID))) {
                                WalletTradeRow(model: model, trade: trade, showsItem: true)
                            }
                            .hudRowButton(WalletTradeRow.rowStyle)
                        }, header: {
                            HUDSectionHeader(Text(verbatim: WalletText.day(day.date, now: now))) {
                                Text("\(day.trades.count) trades")
                            }
                        })
                    }
                }
            }

            Section {
                HUDFootnote("The spread compares the average sell and buy price inside these 30 days only. Sales tax and broker’s fees are journal entries; they are counted in the strip above.")
                    .hudBareRow()
            }
        }
    }
}

/// Trades of one UTC day, newest first.
struct WalletTradeDay: Identifiable {
    var date: Date
    var trades: [WalletTransaction]
    var id: Date { date }

    static func days(from trades: [WalletTransaction]) -> [WalletTradeDay] {
        var days: [WalletTradeDay] = []
        for trade in trades.sorted(by: { $0.date != $1.date ? $0.date > $1.date : $0.id > $1.id }) {
            let start = WalletText.utc.startOfDay(for: trade.date)
            if days.last?.date == start {
                days[days.count - 1].trades.append(trade)
            } else {
                days.append(WalletTradeDay(date: start, trades: [trade]))
            }
        }
        return days
    }
}

/// One type's trades: sold and bought with their averages, the two as a bar, the spread.
private struct WalletItemRow: View {
    static let rowStyle = HUDRowStyle(minHeight: 72, verticalPadding: 11)

    let model: WalletModel
    let item: WalletMarketItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HUDItemIcon(typeID: TypeID(rawValue: UInt32(clamping: item.typeID)), size: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: model.typeName(item.typeID))
                        .font(.hudBody)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: WalletText.signed(item.netFlow))
                        .font(HUDFont.mono(14, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(WalletText.color(item.netFlow))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                HStack(spacing: 12) {
                    if let average = item.averageSell {
                        Text("Sold \(Text(verbatim: "\(MarketFormat.quantity(item.soldQuantity)) · avg \(ISK.priceFigure(average))").foregroundStyle(Color.hudInk))")
                    }
                    if let average = item.averageBuy {
                        Text("Bought \(Text(verbatim: "\(MarketFormat.quantity(item.boughtQuantity)) · avg \(ISK.priceFigure(average))").foregroundStyle(Color.hudInk))")
                    }
                }
                .font(.hudMicro)
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                HStack(spacing: 10) {
                    HUDSplitBar(leading: item.soldValue, trailing: item.boughtValue)
                    if let spread = item.spread {
                        Text("Spread \(MarketFormat.signedPercent(spread))")
                            .font(.hudMicro)
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
        .hudRow(Self.rowStyle)
    }
}

/// One trade: the side, quantity at price, the client, where and when, the signed total.
struct WalletTradeRow: View {
    static let rowStyle = HUDRowStyle(minHeight: 60, verticalPadding: 10)

    let model: WalletModel
    let trade: WalletTransaction
    /// The item's icon and name lead the row; off on the item's own screen.
    var showsItem = false

    var body: some View {
        HStack(alignment: showsItem ? .top : .center, spacing: 12) {
            if showsItem {
                HUDItemIcon(typeID: TypeID(rawValue: UInt32(clamping: trade.typeID)), size: 36)
            } else {
                sideTag
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if showsItem {
                        Text(verbatim: model.typeName(trade.typeID))
                            .font(.hudBody)
                            .lineLimit(1)
                    } else {
                        Text(verbatim: WalletText.trade(quantity: trade.quantity, unitPrice: trade.unitPrice))
                            .font(HUDFont.mono(13, weight: .medium, relativeTo: .subheadline))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(verbatim: WalletText.signed(trade.total))
                        .font(HUDFont.mono(14, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(WalletText.color(trade.total))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                if showsItem {
                    HStack(spacing: 8) {
                        sideTag
                        Text(verbatim: WalletText.trade(quantity: trade.quantity, unitPrice: trade.unitPrice))
                            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(Color.hudInkBodyMuted)
                            .lineLimit(1)
                    }
                }
                place
                    .font(.hudMicro)
                    .tracking(0.5)
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
            }
        }
        .hudRow(Self.rowStyle)
    }

    private var sideTag: some View {
        HUDOutlineTag(text: trade.isBuy ? Text("Buy") : Text("Sell"),
                      color: trade.isBuy ? .hudInkBodyMuted : .hudAccent)
    }

    /// `ORIN VAEL · RENS 0.9 · 11:47`; on the item's screen the date leads.
    private var place: Text {
        var parts: [Text] = []
        if !showsItem {
            parts.append(Text(verbatim: "\(EVETime.monthDay(trade.date))"))
        } else {
            parts.append(Text(verbatim: EVETime.time(trade.date)))
        }
        if let client = model.name(trade.clientID) {
            parts.append(Text(verbatim: client.uppercased()))
        }
        if let system = model.system(ofLocation: trade.locationID) {
            parts.append(HUDPlaceBlock.system(name: system.name, security: system.securityStatus))
        }
        return HUDPlaceBlock.joined(parts) ?? Text(verbatim: "")
    }
}
