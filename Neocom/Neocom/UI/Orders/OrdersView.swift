import BusinessKit
import MarketKit
import SDEKit
import SwiftUI

/// The Market Orders section: the character's open sell and buy orders and 90 days of history,
/// under a strip that sums the open ones. A row opens the order (`OrderDetailView`).
///
/// `OrdersSheet` fetches, `OrdersModel` names and positions; flags (undercut, outbid) come from
/// books the market already holds.
struct OrdersView: View {
    var scope: DataScope = .character

    var body: some View {
        SDESectionView { database in
            if scope == .corporation {
                CorporationOrdersBody(database: database)
            } else {
                OrdersBody(database: database)
            }
        }
        .hudScreen()
        .navigationTitle("Market Orders")
        .navigationBarTitleDisplayMode(.inline)
        .corporationSubtitle(scope)
    }
}

enum OrdersRoute: Hashable {
    case order(Int64)
    /// The market of a type in the region of the order.
    case market(typeID: Int64, regionID: Int64)
}

private struct OrdersBody: View {
    let database: SDEDatabase

    @Environment(AccountStore.self) private var accounts
    @Environment(MarketSheet.self) private var market

    var body: some View {
        if let sheet = accounts.currentOrders {
            OrdersScreen(sheet: sheet, market: market, characterSheet: accounts.currentSheet, database: database)
                // Another character gets its own model.
                .id(ObjectIdentifier(sheet))
        }
    }
}

private struct CorporationOrdersBody: View {
    let database: SDEDatabase

    @Environment(AccountStore.self) private var accounts
    @Environment(MarketSheet.self) private var market

    var body: some View {
        if let sheet = accounts.currentCorporationOrders {
            OrdersScreen(sheet: sheet, market: market, characterSheet: accounts.currentSheet,
                         corporation: accounts.currentCorporation, database: database)
                .id(ObjectIdentifier(sheet))
        } else {
            NoCorporationView()
        }
    }
}

private enum OrdersTab: Hashable {
    case sell
    case buy
    case history
}

private struct OrdersScreen: View {
    @State private var model: OrdersModel
    @State private var tab: OrdersTab = .sell

    init(sheet: any OrdersSource, market: MarketSheet, characterSheet: CharacterSheet?,
         corporation: CorporationSheet? = nil, database: SDEDatabase) {
        _model = State(initialValue: OrdersModel(sheet: sheet, market: market, characterSheet: characterSheet,
                                                 corporation: corporation, database: database))
    }

    var body: some View {
        let sheet = model.sheet
        Group {
            if sheet.access != .granted {
                HUDList {
                    Section {
                        accessPanel(sheet.access)
                            .hudBareRow()
                    }
                }
            } else {
                TimelineView(.everyMinute) { context in
                    OrdersList(model: model, tab: $tab, now: context.date)
                }
            }
        }
        .task {
            async let divisions: Void = model.ensureDivisionsFresh()
            await sheet.ensureFresh()
            await divisions
        }
        .task(id: sheet.open.revision + sheet.history.revision) {
            await model.resolveNames()
            model.refreshPositions()
        }
        .refreshableCommand {
            async let roles: Void = model.refreshRoles()
            await sheet.refresh()
            await roles
        }
        .navigationDestination(for: OrdersRoute.self) { route in
            switch route {
            case let .order(id):
                OrderDetailView(model: model, orderID: id)
            case let .market(typeID, regionID):
                MarketTypeView(typeID: TypeID(rawValue: UInt32(clamping: typeID)), regionID: regionID)
            }
        }
    }

    @ViewBuilder
    private func accessPanel(_ access: BusinessAccess) -> some View {
        if model.isCorporation {
            HUDBusinessAccessPanel(access: access, title: Text("No Corporation Market Access"),
                                   message: Text("Corporation orders need one more permission. Sign in to EVE again and allow Neocom to read your corporation's market orders."))
        } else {
            HUDBusinessAccessPanel(access: access, title: Text("No Market Access"),
                                   message: Text("Your own orders need one more permission. Sign in to EVE again and allow Neocom to read your market orders."))
        }
    }
}

private struct OrdersList: View {
    let model: OrdersModel
    @Binding var tab: OrdersTab
    let now: Date

    @State private var walletFilter: Int?

    var body: some View {
        let sheet = model.sheet
        if sheet.open.value == nil {
            HUDList {
                if let error = sheet.open.state.error {
                    Section {
                        HUDEmptyPanel(title: Text("Orders Unavailable"), message: Text(error.localizedDescription)) {
                            Button("Retry") { Task { await sheet.refresh() } }
                                .hudProminentButton()
                        }
                        .hudBareRow()
                    }
                } else {
                    Section {
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
        let open = model.open.filter { matches($0) }
        let sells = open.filter { !$0.isBuyOrder }.sorted { $0.expires < $1.expires }
        let buys = open.filter(\.isBuyOrder).sorted { $0.expires < $1.expires }
        let history = model.history.filter { matches($0) }.sorted { $0.issued > $1.issued }
        let summary = OrdersSummary(open, now: now)

        return HUDList {
            Section {
                SummaryPanel(summary: summary, snapshot: model.sheet.open, now: now)
                    .hudLeadingBlock()
            }

            Section {
                Picker("Orders", selection: $tab) {
                    Text(verbatim: "\(String(localized: "Sell")) · \(sells.count)").tag(OrdersTab.sell)
                    Text(verbatim: "\(String(localized: "Buy")) · \(buys.count)").tag(OrdersTab.buy)
                    Text("History").tag(OrdersTab.history)
                }
                .pickerStyle(.segmented)
                .hudBareRow()
            }

            switch tab {
            case .sell:
                openSection(sells, title: String(localized: "Selling"))
            case .buy:
                openSection(buys, title: String(localized: "Buying"))
            case .history:
                historySection(history)
            }

            Section {
                HUDFootnote(tab == .history
                            ? "Expired and cancelled orders from the last 90 days. An expired order with nothing left traded in full."
                            : model.isCorporation
                            ? "EVE refreshes the corporation's orders every 20 minutes. Undercut and outbid are checked against the order book of the order’s region, once you have opened that market or the order. Change or cancel orders in the EVE client."
                            : "EVE refreshes your orders every 20 minutes. Undercut and outbid are checked against the order book of the order’s region, once you have opened that market or the order. Change or cancel orders in the EVE client.")
                    .hudBareRow()
            }
        }
        .toolbar {
            if model.walletDivisions.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Wallet Division", selection: $walletFilter) {
                            Text("All Divisions").tag(Int?.none)
                            ForEach(model.walletDivisions, id: \.self) { number in
                                Text(verbatim: model.walletName(division: number)).tag(Int?.some(number))
                            }
                        }
                    } label: {
                        Label("Filter by Wallet Division", systemImage: walletFilter == nil
                              ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
        }
    }

    private func matches(_ order: CharacterOrder) -> Bool {
        walletFilter == nil || order.walletDivision == walletFilter
    }

    @ViewBuilder
    private func openSection(_ orders: [CharacterOrder], title: String) -> some View {
        if orders.isEmpty {
            Section {
                HUDEmptyPanel(title: Text(tab == .sell ? String(localized: "No Sell Orders") : String(localized: "No Buy Orders")),
                              message: Text(model.isCorporation
                                            ? "Orders your corporation places show here: what has traded, what is left and when each one expires."
                                            : "Orders you place in the EVE client show here: what has traded, what is left and when each one expires."))
                    .hudBareRow()
            }
        } else {
            let total = orders.reduce(0) { $0 + $1.remainingValue }
            HUDListSection(orders, row: { order in row(order) }, header: {
                HUDSectionHeader(Text("\(title) · \(orders.count)")) {
                    Text(verbatim: "\(ISK.compact(total)) ISK")
                }
            })
        }
    }

    @ViewBuilder
    private func historySection(_ orders: [CharacterOrder]) -> some View {
        if model.sheet.history.value == nil {
            Section {
                if let error = model.sheet.history.state.error {
                    HUDEmptyPanel(title: Text("History Unavailable"), message: Text(error.localizedDescription)) {
                        Button("Retry") { Task { await model.sheet.refresh() } }
                            .hudProminentButton()
                    }
                    .hudBareRow()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .hudBareRow()
                }
            }
        } else if orders.isEmpty {
            Section {
                HUDEmptyPanel(title: Text("No Order History"),
                              message: Text(model.isCorporation
                                            ? "Orders your corporation places show here: what has traded, what is left and when each one expires."
                                            : "Orders you place in the EVE client show here: what has traded, what is left and when each one expires."))
                    .hudBareRow()
            }
        } else {
            HUDListSection(orders, row: { order in row(order) }, header: {
                HUDSectionHeader(Text("Last 90 days · \(orders.count)"))
            })
        }
    }

    private func row(_ order: CharacterOrder) -> some View {
        NavigationLink(value: OrdersRoute.order(order.id)) {
            OrderRow(order: order, model: model, now: now)
        }
        .hudRowButton(OrderRow.rowStyle)
        .contextMenu {
            HUDTypeCopyButtons(typeID: order.typeID, name: model.typeName(order))
            HUDCopyButton(price: order.price)
        }
    }
}

// MARK: - Summary

private struct SummaryPanel: View {
    let summary: OrdersSummary
    let snapshot: ESISnapshot<ESIOrderList>?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: HUDMetrics.headerSpacing) {
            HUDPanel {
                HUDStatStrip(items: [
                    .init(id: 0, label: Text("Open"), value: Text(verbatim: "\(summary.openCount)")),
                    .init(id: 1, label: Text("Selling"), value: Text(verbatim: figure(summary.sellTotal, summary.sellCount))),
                    .init(id: 2, label: Text("Buying"), value: Text(verbatim: figure(summary.buyTotal, summary.buyCount))),
                    .init(id: 3, label: Text("Escrow"), value: Text(verbatim: figure(summary.escrow, summary.buyCount))),
                ])
            }
            HStack(spacing: 8) {
                if let snapshot {
                    HUDFreshnessChip(snapshot, now: now)
                }
                if summary.expiringSoonCount > 0 {
                    Spacer(minLength: 8)
                    HUDStatusChip(text: Text("\(summary.expiringSoonCount) expiring"), color: .hudWarn)
                        .padding(.horizontal, HUDMetrics.headerFaceInset)
                }
            }
        }
    }

    private func figure(_ value: Double, _ count: Int) -> String {
        count == 0 ? "0" : ISK.compact(value)
    }
}

// MARK: - Row

private struct OrderRow: View {
    static let rowStyle = HUDRowStyle(minHeight: 84, verticalPadding: 12)

    let order: CharacterOrder
    let model: OrdersModel
    let now: Date

    var body: some View {
        let flag = order.flag(position: model.position(of: order), now: now)
        let badge = OrdersText.badge(for: order, flag: flag)
        let isOpen = order.state == .open
        HStack(alignment: .top, spacing: 12) {
            HUDItemIcon(typeID: TypeID(rawValue: UInt32(clamping: order.typeID)), size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: model.typeName(order))
                        .font(.hudBody)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: ISK.price(order.price))
                        .font(HUDFont.mono(13, weight: .semibold, relativeTo: .subheadline))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
                Text(verbatim: model.locationName(order))
                    .font(.hudCaption)
                    .foregroundStyle(Color.hudInkBodyMuted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    meta
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if model.isCorporation {
                        HUDMetaBadge(text: model.walletName(order).map { Text(verbatim: $0) } ?? Text("Corp"))
                    } else if order.isCorporation {
                        HUDMetaBadge(text: Text("Corp"))
                    }
                    if let badge {
                        HUDStatusChip(text: Text(verbatim: badge.title), color: badge.color, mark: .dot)
                            .font(.hudMicro)
                    }
                }
                .font(.hudMicro)
                .tracking(0.5)
                .foregroundStyle(Color.hudInkMuted)
                HUDOrderFillBar(fraction: order.remainingFraction,
                                tint: isOpen ? .hudAccent : .hudLineLeader,
                                caption: Text("\(OrdersText.quantity(order)) left"))
                    .padding(.top, 2)
            }
        }
        .hudRow(Self.rowStyle)
    }

    /// `RENS 0.9 · 3D 04H LEFT · RANGE STATION`, or for history `SELL · 2026.09.28 · 14D`.
    private var meta: Text {
        var parts: [Text] = []
        if let system = model.system(of: order) {
            parts.append(OrdersText.system(system))
        }
        if order.state == .open {
            parts.append(Text("\(EVETime.duration(order.timeLeft(at: now)).uppercased()) LEFT"))
            if order.isBuyOrder {
                parts.append(Text("RANGE \(MarketFormat.range(order.range).uppercased())"))
                if order.minVolume > 1 {
                    parts.append(Text("MIN \(MarketFormat.quantity(order.minVolume))"))
                }
            }
        } else {
            parts.append(Text(verbatim: "\(OrdersText.side(order).uppercased()) · \(EVETime.date(order.issued)) · \(String(localized: "\(order.duration)D", comment: "Duration in days, abbreviated"))"))
        }
        return OrdersText.joined(parts)
    }
}

#if DEBUG
#Preview("Summary") {
    HUDList {
        Section {
            SummaryPanel(summary: OrdersSummary(OrdersFixture.orders, now: OrdersFixture.now), snapshot: nil, now: OrdersFixture.now)
                .hudBareRow()
        }
    }
}

enum OrdersFixture {
    static let now = Date(timeIntervalSince1970: 1_792_000_000)
    static let orders: [CharacterOrder] = [
        CharacterOrder(id: 1, typeID: 626, regionID: 10_000_030, locationID: 60_004_588, isBuyOrder: false,
                       price: 9_250_000, volumeRemain: 4, volumeTotal: 6, duration: 90,
                       issued: now.addingTimeInterval(-20 * 86_400)),
        CharacterOrder(id: 2, typeID: 626, regionID: 10_000_030, locationID: 60_004_588, isBuyOrder: true,
                       price: 7_664_000, volumeRemain: 1, volumeTotal: 3, range: "station", duration: 30,
                       issued: now.addingTimeInterval(-8 * 86_400), escrow: 7_664_000),
    ]
}
#endif
