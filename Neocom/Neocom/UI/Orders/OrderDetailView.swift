import BusinessKit
import MarketKit
import SDEKit
import SwiftUI

/// One order of the character: its worth, its place in the region's book, terms, location and
/// end. Open orders read their book on arrival; history entries have no market block.
struct OrderDetailView: View {
    let model: OrdersModel
    let orderID: Int64

    var body: some View {
        Group {
            if let order = model.order(id: orderID) {
                TimelineView(.everyMinute) { context in
                    OrderDetailList(model: model, order: order, now: context.date)
                }
                .task(id: orderID) { await model.loadDetail(order) }
                .refreshableCommand { await model.refreshDetail(order) }
                .navigationTitle(model.typeName(order))
                .navigationSubtitle(Text(order.state == .open ? (order.isBuyOrder ? String(localized: "Buy order") : String(localized: "Sell order"))
                                                              : String(localized: "Order history")))
            } else {
                ContentUnavailableView("Order Not Found", systemImage: "questionmark.circle",
                                       description: Text("The order is no longer in the list."))
                    .navigationTitle("Market Order")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .hudScreen()
    }
}

private struct OrderDetailList: View {
    let model: OrdersModel
    let order: CharacterOrder
    let now: Date

    @Environment(AccountStore.self) private var accounts

    private var position: OrderBookPosition? { model.position(of: order) }
    private var flag: OrderFlag? { order.flag(position: position, now: now) }
    private var isOpen: Bool { order.state == .open }
    private var typeID: TypeID { TypeID(rawValue: UInt32(clamping: order.typeID)) }

    var body: some View {
        HUDList {
            Section { header.hudBareRow() }
            if isOpen {
                market
            }
            facts
            location
            time
            Section {
                HUDFootnote(Text(footnote)).hudBareRow()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        let badge = OrdersText.badge(for: order, flag: flag)
        return HUDPanel(tone: flag == nil || !isOpen ? .normal : .warn) {
            NavigationLink(value: DatabaseRoute.type(typeID)) {
                HStack(spacing: 12) {
                    HUDItemIcon(typeID: typeID, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: model.typeName(order))
                            .font(HUDFont.display(18, weight: .bold, relativeTo: .headline))
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .lineLimit(2)
                        Text(verbatim: kind)
                            .font(.hudMicro)
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let badge {
                        HUDStatusChip(text: Text(verbatim: badge.title), color: badge.color, mark: .dot)
                    } else if isOpen {
                        HUDStatusChip(text: Text("Open"), color: .hudAccent, mark: .dot)
                    }
                    HUDChevron()
                }
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HUDPanelRule()
            HUDStatStrip(items: [
                .init(id: 0, label: Text("Price / Unit"), value: Text(verbatim: ISK.compact(order.price))),
                .init(id: 1, label: Text("Left"), value: Text(verbatim: OrdersText.quantity(order))),
                .init(id: 2, label: order.isBuyOrder ? Text("To Spend") : Text("To Earn"),
                      value: Text(verbatim: ISK.compact(order.remainingValue))),
            ])
            HUDPanelRule()
            HUDOrderFillBar(fraction: order.remainingFraction,
                            tint: isOpen ? .hudAccent : .hudLineLeader,
                            caption: Text(verbatim: "\(order.isBuyOrder ? String(localized: "\(MarketFormat.quantity(order.volumeTraded)) bought") : String(localized: "\(MarketFormat.quantity(order.volumeTraded)) sold")) · \(String(localized: "\(MarketFormat.quantity(order.volumeRemain)) left"))"))
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.vertical, 12)
        }
        .foregroundStyle(Color.hudInk)
    }

    private var kind: String {
        let side = order.isBuyOrder ? String(localized: "Buy order") : String(localized: "Sell order")
        guard let group = model.types[order.typeID]?.group else { return side }
        return "\(side) · \(group)"
    }

    // MARK: Market

    @ViewBuilder
    private var market: some View {
        let region = model.regionName(order)
        HUDListSection {
            if let position {
                HUDReadoutRow(order.isBuyOrder ? Text("Best Buy") : Text("Best Sell")) {
                    Text(verbatim: ISK.price(position.bestPrice))
                }
                HUDReadoutRow("At", value: bestPlace(position))
                HUDReadoutRow("Your Place") {
                    Text(verbatim: place(position))
                        .foregroundStyle(position.isFirst ? Color.hudOk : Color.hudWarn)
                }
                if let note = note(position) {
                    Text(verbatim: note)
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .lineSpacing(3)
                        .foregroundStyle(Color.hudWarnNoteInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hudRow(HUDRowStyle(background: .hudWarnNoteBg, minHeight: 0, verticalPadding: 10))
                }
            } else if let error = model.bookError(order) {
                Text(verbatim: error.localizedDescription)
                    .font(.hudCaption)
                    .foregroundStyle(Color.hudInkMuted)
                    .hudRow()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .hudRow()
            }
            NavigationLink(value: OrdersRoute.market(typeID: order.typeID, regionID: order.regionID)) {
                HStack {
                    Text("Open Market")
                        .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Color.hudAccent)
                    Spacer(minLength: 8)
                    HUDChevron()
                }
                .hudRow()
            }
            .hudRowButton()
        } header: {
            HUDSectionHeader(Text("Market · \(region ?? "—")"))
        }
    }

    /// Where the best order is: `Emolgranlan · 7 J`, or `Rens · you` when the best is ours.
    private func bestPlace(_ position: OrderBookPosition) -> String {
        guard position.bestOrderID != nil else {
            let name = model.system(of: order)?.name ?? "—"
            return String(localized: "\(name) · you")
        }
        guard let id = model.bestSystems[order.id] else { return "—" }
        let name = model.systems[id]?.name ?? "—"
        if let jumps = model.jumps(toSystem: id) {
            return "\(name) · \(MarketFormat.jumps(jumps))"
        }
        return name
    }

    /// `FIRST OF 10`, `#2 OF 22 · +0.5%`.
    private func place(_ position: OrderBookPosition) -> String {
        if position.isFirst {
            return String(localized: "First of \(position.count)")
        }
        return "\(String(localized: "#\(position.rank) of \(position.count)")) · \(MarketFormat.signedPercent(position.gapToBest))"
    }

    private func note(_ position: OrderBookPosition) -> String? {
        guard flag == .undercut || flag == .outbid else { return nil }
        let at = model.bestSystems[order.id].flatMap { model.systems[$0]?.name } ?? String(localized: "another station")
        let difference = abs(order.price - position.bestPrice)
        let amount = ISK.price(difference)
        if order.isBuyOrder {
            return String(localized: "A buyer at \(at) pays \(amount) more. Raise your price in the EVE client to be first again.")
        }
        return String(localized: "A seller at \(at) is \(amount) cheaper. Lower your price in the EVE client to be first again.")
    }

    // MARK: Facts

    private var facts: some View {
        HUDListSection(Text(String(localized: "orders.detail.order", defaultValue: "Order", comment: "Section header: the market order itself"))) {
            HUDReadoutRow("Side", value: OrdersText.side(order))
            HUDReadoutRow("Price", value: ISK.price(order.price))
            HUDReadoutRow("Volume", value: String(localized: "\(MarketFormat.quantity(order.volumeRemain)) of \(MarketFormat.quantity(order.volumeTotal)) left"))
            HUDReadoutRow(Text(String(localized: "market.order.range", defaultValue: "Range", comment: "How far a buy order reaches (station, system, jumps)")), value: OrdersText.rangeLong(order.range))
            if order.isBuyOrder {
                HUDReadoutRow("Min Volume", value: MarketFormat.quantity(order.minVolume))
                if let escrow = order.escrow {
                    HUDReadoutRow("Escrow", value: ISK.price(escrow))
                }
            }
            HUDReadoutRow("Placed For", value: order.isCorporation
                          ? String(localized: "Corporation")
                          : accounts.currentAccount?.characterName ?? "—")
            if !isOpen {
                HUDReadoutRow("State") {
                    Text(verbatim: stateText)
                        .foregroundStyle(order.outcome == .filled ? Color.hudOk : Color.hudInk)
                }
            }
            HUDReadoutRow("Order ID", value: String(order.id))
        }
    }

    private var stateText: String {
        switch order.outcome {
        case .filled: String(localized: "Expired · traded in full")
        case .cancelled: String(localized: "Cancelled")
        case .expired, .open: String(localized: "Expired")
        }
    }

    // MARK: Location

    private var location: some View {
        HUDListSection("Location") {
            HUDPlaceBlock(name: model.locationName(order), line: locationLine(model.system(of: order)))
                .hudRow()
        }
    }

    private func locationLine(_ system: MarketSystemRow?) -> Text? {
        var details: [String?] = [model.regionName(order)]
        if let jumps = model.jumps(to: order) {
            if let pilot = model.pilotSystem {
                details.append(jumps == 0
                               ? String(localized: "In \(pilot.name)")
                               : String(localized: "\(MarketFormat.jumps(jumps)) from \(pilot.name)"))
            } else {
                details.append(MarketFormat.jumps(jumps))
            }
        }
        return HUDPlaceBlock.line(systemName: system?.name, security: system?.securityStatus, details: details)
    }

    // MARK: Time

    private var time: some View {
        HUDListSection("Time") {
            HUDReadoutRow("Issued", value: EVETime.dateTime(order.issued))
            HUDReadoutRow("Duration", value: String(localized: "\(order.duration) days"))
            HUDReadoutRow(isOpen ? Text("Expires") : Text("Would Expire"), value: EVETime.dateTime(order.expires))
            if isOpen {
                HUDReadoutRow("Time Left") {
                    Text(verbatim: EVETime.duration(order.timeLeft(at: now)))
                        .foregroundStyle(order.isExpiringSoon(at: now) ? Color.hudWarn : Color.hudInk)
                }
            }
        }
    }

    private var footnote: String {
        if !isOpen {
            return String(localized: "History keeps expired and cancelled orders for 90 days. ESI does not say when an order closed, only when it would have expired.")
        }
        let change = String(localized: "Change or cancel the order in the EVE client.")
        return order.isBuyOrder
            ? String(localized: "ISK in escrow comes back if the order expires or you cancel it.") + " " + change
            : change
    }
}
