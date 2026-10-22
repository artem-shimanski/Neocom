import LiteRowUI
import MarketKit
import SDEKit
import SwiftUI

/// The order book: sell or buy, a quantity calculator against it, and the best orders with
/// where they are and how far from the pilot. The top `MarketTypeModel.visibleRows` first, the
/// whole side on request.
struct MarketOrdersSection: View {
    let model: MarketTypeModel
    let regionName: String?

    @State private var side: MarketSide = .sell
    @State private var showsAll = false
    @State private var quantity: Int64 = 10
    @LiteQuery private var pilotSystem: [MarketSystemRow]

    init(model: MarketTypeModel, regionName: String?, pilotSystemID: Int64?) {
        self.model = model
        self.regionName = regionName
        _pilotSystem = LiteQuery(pilotSystemID.map { MarketBrowser.systems([MarketFormat.systemID($0)]) })
    }

    /// One row of the card; the calculator and the "show more" button are rows of the same list, as
    /// a side of the book holds thousands of orders.
    private enum Row: Identifiable {
        case calculator
        case total(MarketFill)
        case average(MarketFill)
        case source(MarketFill)
        case order(MarketOrderRow)
        case more(count: Int, units: Int64)
        case status

        var id: String {
            switch self {
            case .calculator: "calculator"
            case .total: "total"
            case .average: "average"
            case .source: "source"
            case let .order(row): "order-\(row.id)"
            case .more: "more"
            case .status: "status"
            }
        }
    }

    var body: some View {
        HUDListSection(rows, row: { row in
            content(of: row)
        }, header: {
            VStack(spacing: HUDMetrics.headerSpacing) {
                HUDSectionHeader(Text("Orders")) {
                    if let system = pilotSystem.first {
                        Text("Jumps from \(system.name)")
                    }
                }
                Picker("Side", selection: $side) {
                    Text(verbatim: "\(String(localized: "Sell")) · \(model.book(.sell).count)").tag(MarketSide.sell)
                    Text(verbatim: "\(String(localized: "Buy")) · \(model.book(.buy).count)").tag(MarketSide.buy)
                }
                .pickerStyle(.segmented)
                .textCase(nil)
            }
        })
        .onChange(of: side) { showsAll = false }
    }

    private var rows: [Row] {
        guard model.orders.value != nil else { return [.status] }
        let book = model.book(side)
        guard !book.isEmpty else { return [.status] }
        let fill = model.fill(quantity, side: side)
        var rows: [Row] = [.calculator, .total(fill), .average(fill), .source(fill)]
        rows += model.rows(side, limit: showsAll ? nil : MarketTypeModel.visibleRows).map(Row.order)
        if book.count > MarketTypeModel.visibleRows {
            rows.append(.more(count: book.count, units: book.reduce(0) { $0 + $1.volumeRemain }))
        }
        return rows
    }

    @ViewBuilder
    private func content(of row: Row) -> some View {
        switch row {
        case .calculator:
            calculator
        case let .total(fill):
            HUDReadoutRow("Total") {
                if fill.isComplete {
                    Text(verbatim: ISK.price(fill.total))
                } else {
                    Text(verbatim: "\(ISK.price(fill.total)) · \(String(localized: "Only \(MarketFormat.quantity(fill.filled))").uppercased())")
                        .foregroundStyle(Color.hudWarn)
                }
            }
        case let .average(fill):
            HUDReadoutRow("Average", value: average(fill))
        case let .source(fill):
            HUDReadoutRow(Text(String(localized: "market.fill.from", defaultValue: "From", comment: "Where the filled quantity comes from: orders used and their systems")), value: source(fill))
        case let .order(order):
            MarketOrderRowView(row: order, side: side)
                .contextMenu { HUDCopyButton(price: order.order.price) }
        case let .more(count, units):
            Button {
                showsAll.toggle()
            } label: {
                HStack(spacing: 10) {
                    Text(showsAll ? "Show top \(MarketTypeModel.visibleRows)" : moreTitle(count))
                        .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Color.hudAccent)
                    Spacer(minLength: 8)
                    Text(verbatim: String(localized: "\(MarketFormat.quantity(units)) Units"))
                        .font(.hudMicro)
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                }
                .hudRow(HUDRowStyle(minHeight: 50, verticalPadding: 8))
            }
            .hudRowButton(HUDRowStyle(minHeight: 50, verticalPadding: 8))
            .task(id: showsAll) {
                if showsAll { await model.resolveJumps(for: model.rows(side)) }
            }
        case .status:
            status
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))
        }
    }

    private func moreTitle(_ count: Int) -> LocalizedStringKey {
        side == .sell ? "All \(count) sell orders" : "All \(count) buy orders"
    }

    @ViewBuilder private var status: some View {
        if model.orders.value == nil {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            Text(side == .sell ? String(localized: "No sell orders in \(regionName ?? "").")
                               : String(localized: "No buy orders in \(regionName ?? "")."))
                .font(.hudCaption)
                .foregroundStyle(Color.hudInkMuted)
        }
    }

    // MARK: Calculator

    private var calculator: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(side == .sell ? String(localized: "Buy") : String(localized: "Sell"))
                    .font(.body)
                Text(verbatim: MarketFormat.quantity(quantity))
                    .font(HUDFont.mono(15, weight: .semibold, relativeTo: .body))
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            Stepper {
                Text("Quantity")
            } onIncrement: {
                quantity += quantity >= 10 ? 5 : 1
            } onDecrement: {
                quantity = max(1, quantity - (quantity > 10 ? 5 : 1))
            }
            .labelsHidden()
            .accessibilityValue(Text(verbatim: MarketFormat.quantity(quantity)))
        }
        .padding(.leading, HUDMetrics.gutter)
        .padding(.trailing, 12)
        .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 52, verticalPadding: 10))
    }

    /// `9 251 000 ISK · +0.6% VS BEST`.
    private func average(_ fill: MarketFill) -> String {
        guard let average = fill.averagePrice else { return "—" }
        guard let best = model.book(side).first?.price, best > 0 else { return ISK.price(average) }
        let versus = MarketFormat.signedPercent(average / best - 1)
        return "\(ISK.price(average)) · \(versus) \(String(localized: "vs best").uppercased())"
    }

    /// `3 ORDERS · RENS, EMOLGRANLAN`.
    private func source(_ fill: MarketFill) -> String {
        let systems = fill.systemIDs.map { model.systems[$0]?.name ?? "—" }
        let orders = String(localized: "\(fill.ordersUsed) orders").uppercased()
        return systems.isEmpty ? orders : "\(orders) · \(systems.joined(separator: ", ").uppercased())"
    }
}

/// One order: price and quantity, the station, then the system with its security, the jumps
/// from the pilot, and for a buy order how far it reaches and the least it takes.
private struct MarketOrderRowView: View {
    let row: MarketOrderRow
    let side: MarketSide

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: ISK.price(row.order.price))
                    .font(HUDFont.mono(15, weight: .semibold, relativeTo: .body))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "\(MarketFormat.quantity(row.order.volumeRemain)) / \(MarketFormat.quantity(row.order.volumeTotal))")
                    .font(HUDFont.mono(12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(Color.hudInkBodyMuted)
                    .lineLimit(1)
            }
            Text(verbatim: location)
                .font(HUDFont.display(13, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(row.stationName == nil ? Color.hudInkMuted : Color.hudInk)
                .lineSpacing(1)
            details
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .foregroundStyle(Color.hudInkMuted)
        }
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
        .accessibilityElement(children: .combine)
    }

    private var location: String {
        if let name = row.stationName { return name }
        return row.isStructure ? String(localized: "Unknown structure") : String(localized: "Unknown station")
    }

    /// `RENS 0.9 · 2 J · RANGE STATION · MIN 5`.
    private var details: Text {
        var parts: [String] = []
        if let jumps = row.jumps { parts.append(MarketFormat.jumps(jumps).uppercased()) }
        if side == .buy {
            parts.append("\(String(localized: "market.order.range", defaultValue: "Range", comment: "How far a buy order reaches (station, system, jumps)")) \(MarketFormat.range(row.order.range))".uppercased())
        }
        if row.order.minVolume > 1 {
            parts.append("\(String(localized: "Min")) \(MarketFormat.quantity(row.order.minVolume))".uppercased())
        }
        let tail = parts.map { " · \($0)" }.joined()
        guard let name = row.systemName else {
            return Text(verbatim: "—\(tail)")
        }
        var system = Text(verbatim: name.uppercased())
        if let security = row.securityStatus {
            let sec = Text(verbatim: SecurityStatus.string(security)).foregroundStyle(SecurityStatus.color(security))
            system = Text("\(system) \(sec)")
        }
        return Text("\(system)\(Text(verbatim: tail))")
    }
}
