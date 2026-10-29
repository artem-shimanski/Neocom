import BusinessKit
import LiteRowUI
import SDEKit
import SwiftUI

/// The Wallet section: the character's balance over 30 days, what came in and went out by
/// category, and the way to the journal and the market transactions.
///
/// `WalletSheet` fetches, `WalletModel` names and sums. A corporation division opens the same
/// overview from `CorporationWalletsView`.
struct WalletView: View {
    var body: some View {
        SDESectionView { database in
            WalletBody(database: database)
        }
        .hudScreen()
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Where a Wallet screen leads; `division` is `nil` for the character's own wallet.
struct WalletRoute: Hashable {
    enum Page: Hashable {
        case overview
        case journal(WalletCategory?)
        case entry(Int64)
        case market
        case item(Int64)
        case memberTaxes
    }

    var division: Int?
    var page: Page
}

private struct WalletBody: View {
    let database: SDEDatabase

    @Environment(AccountStore.self) private var accounts
    @Environment(MarketSheet.self) private var market
    @State private var store = WalletModelStore()

    var body: some View {
        if let sheet = accounts.currentWallet {
            WalletOverviewView(model: store.model(for: sheet, corporation: nil, database: database, market: market))
                // Another character gets its own screen.
                .id(ObjectIdentifier(sheet))
                .walletDestinations(store: store, database: database)
        }
    }
}

extension View {
    /// The Wallet screens, registered once at the root of a section.
    func walletDestinations(store: WalletModelStore, database: SDEDatabase) -> some View {
        navigationDestination(for: WalletRoute.self) { route in
            WalletDestination(route: route, store: store, database: database)
                .liteDatabase(database.database)
        }
    }
}

private struct WalletDestination: View {
    let route: WalletRoute
    let store: WalletModelStore
    let database: SDEDatabase

    @Environment(AccountStore.self) private var accounts
    @Environment(MarketSheet.self) private var market

    var body: some View {
        if let source {
            let model = store.model(for: source, corporation: route.division == nil ? nil : accounts.currentCorporation,
                                    database: database, market: market)
            switch route.page {
            case .overview: WalletOverviewView(model: model)
            case let .journal(category): WalletJournalView(model: model, category: category)
            case let .entry(id): WalletJournalEntryView(model: model, entryID: id)
            case .market: WalletMarketView(model: model)
            case let .item(typeID): WalletMarketItemView(model: model, typeID: typeID)
            case .memberTaxes: CorporationMemberTaxesView(model: model)
            }
        } else {
            NoCorporationView()
                .hudScreen()
        }
    }

    private var source: (any WalletSource)? {
        guard let division = route.division else { return accounts.currentWallet }
        return accounts.currentCorporationWallet?.division(division)
    }
}

// MARK: - Screen frame

/// The frame of every Wallet screen: the access panel, the journal's loading and failure, the
/// fetch, the names and pull-to-refresh. `content` runs under the screen's one clock.
struct WalletScreen<Content: View>: View {
    let model: WalletModel
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        let source = model.source
        Group {
            if source.access != .granted {
                HUDList {
                    Section {
                        WalletAccessPanel(access: source.access, isCorporation: model.isCorporation)
                            .hudBareRow()
                    }
                }
            } else if source.journal.value != nil {
                TimelineView(.everyMinute) { context in
                    content(context.date)
                }
            } else if let error = source.journal.state.error {
                HUDList {
                    Section {
                        HUDEmptyPanel(title: Text("Wallet Unavailable"), message: Text(error.localizedDescription)) {
                            Button("Retry") { Task { await source.refresh() } }
                                .hudProminentButton()
                        }
                        .hudBareRow()
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .hudScreen()
        .task { await source.ensureFresh() }
        .task(id: source.transactions.revision) { await model.resolveNames() }
        .refreshableCommand {
            async let roles: Void = model.corporation?.refresh() ?? ()
            await source.refresh()
            await roles
        }
    }
}

/// A missing scope offers `Grant Access`; a corporation wallet without the role says which one.
struct WalletAccessPanel: View {
    let access: BusinessAccess
    let isCorporation: Bool

    var body: some View {
        if access == .forbidden {
            HUDEmptyPanel(title: Text("No Accountant Role"),
                          message: Text("Corporation wallets need the Accountant or Junior Accountant role. A director grants it in the EVE client."))
        } else if isCorporation {
            HUDBusinessAccessPanel(access: access, title: Text("No Corporation Wallet Access"),
                                   message: Text("Corporation wallets need one more permission. Sign in to EVE again and allow Neocom to read your corporation's wallets."))
        } else {
            HUDBusinessAccessPanel(access: access, title: Text("No Wallet Access"),
                                   message: Text("Your wallet journal needs one more permission. Sign in to EVE again and allow Neocom to read your wallet."))
        }
    }
}

// MARK: - Overview

/// One wallet: the balance and its 30 days, the period's income and expenses by category.
struct WalletOverviewView: View {
    let model: WalletModel

    var body: some View {
        WalletScreen(model: model) { now in
            WalletOverviewList(model: model, now: now)
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .corporationSubtitle(model.isCorporation ? .corporation : .character)
    }
}

private struct WalletOverviewList: View {
    let model: WalletModel
    let now: Date

    @State private var period: WalletPeriod = .month

    var body: some View {
        let summary = model.summary(now: now, period: period)
        HUDList {
            Section {
                WalletHero(model: model, now: now, period: period)
                    .hudLeadingBlock()
            }

            Section {
                Picker("Period", selection: $period) {
                    ForEach(WalletPeriod.allCases, id: \.self) { period in
                        Text(verbatim: WalletText.period(period)).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .hudBareRow()
            }

            Section {
                HUDPanel {
                    HUDStatStrip(items: [
                        .init(id: 0, label: Text("Income"), value: Text(verbatim: WalletText.signed(summary.income)),
                              color: WalletText.color(summary.income)),
                        .init(id: 1, label: Text("Expenses"), value: Text(verbatim: WalletText.signed(-summary.expenses))),
                        .init(id: 2, label: Text("Net"), value: Text(verbatim: WalletText.signed(summary.net)),
                              color: WalletText.color(summary.net)),
                    ])
                }
                .hudBareRow()
            }

            if summary.incomeByCategory.isEmpty && summary.expensesByCategory.isEmpty {
                Section {
                    HUDEmptyPanel(title: Text("No Activity"),
                                  message: Text("Nothing came in or went out of this wallet in the period."))
                        .hudBareRow()
                }
            } else {
                categorySection(summary.incomeByCategory, title: Text("Income"), total: summary.income)
                categorySection(summary.expensesByCategory, title: Text("Expenses"), total: -summary.expenses)
            }

            links

            Section {
                HUDFootnote("EVE keeps 30 days of wallet history; older entries are gone from ESI. The journal refreshes hourly. Tap a category to open the journal filtered to it.")
                    .hudBareRow()
            }
        }
    }

    @ViewBuilder
    private func categorySection(_ totals: [WalletCategoryTotal], title: Text, total: Double) -> some View {
        if !totals.isEmpty {
            HUDListSection(totals, row: { line in
                NavigationLink(value: WalletRoute(division: model.source.division, page: .journal(line.category))) {
                    WalletCategoryRow(line: line)
                }
                .hudRowButton(WalletCategoryRow.rowStyle)
            }, header: {
                HUDSectionHeader(title) {
                    Text(verbatim: WalletText.signed(total))
                }
            })
        }
    }

    private var links: some View {
        let division = model.source.division
        return HUDListSection {
            NavigationLink(value: WalletRoute(division: division, page: .journal(nil))) {
                HUDLinkRowLabel(systemImage: "list.bullet", title: Text("Journal"),
                                subtitle: Text("\(model.entries.count) entries · 30 days"))
            }
            .hudRowButton(.subtitled)
            NavigationLink(value: WalletRoute(division: division, page: .market)) {
                HUDLinkRowLabel(systemImage: WalletText.systemImage(.market), title: Text("Market Transactions"),
                                subtitle: marketSubtitle)
            }
            .hudRowButton(.subtitled)
            if model.isCorporation, division == 1 {
                NavigationLink(value: WalletRoute(division: division, page: .memberTaxes)) {
                    HUDLinkRowLabel(systemImage: WalletText.systemImage(.corporateTaxes), title: Text("Member Taxes"),
                                    subtitle: Text("Bounty and mission tax by member"))
                }
                .hudRowButton(.subtitled)
            }
        }
    }

    private var marketSubtitle: Text {
        let snapshot = model.source.transactions
        if snapshot.value != nil {
            let summary = model.marketSummary
            return Text("\(summary.tradeCount) trades · \(summary.items.count) items")
        }
        if snapshot.state.error != nil { return Text("Unavailable") }
        return Text("Loading…")
    }
}

/// The balance, its change over 30 days and the step chart of it, with the period shaded.
private struct WalletHero: View {
    let model: WalletModel
    let now: Date
    let period: WalletPeriod

    var body: some View {
        let series = model.balanceSeries(now: now)
        let balance = model.source.balance ?? series.last?.balance
        VStack(alignment: .leading, spacing: HUDMetrics.headerSpacing) {
            HUDPanel {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: model.isCorporation ? model.title : String(localized: "Balance"))
                        Spacer(minLength: 8)
                        Text("30 Days")
                    }
                    .font(.hudMicro)
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: balance.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—")
                            .font(.hudFigureXL)
                            .foregroundStyle(Color.hudAccent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(verbatim: "ISK")
                            .font(.hudCaption)
                            .foregroundStyle(Color.hudInkMuted)
                    }
                    if let first = series.first, let last = series.last {
                        let net = last.balance - first.balance
                        Text("\(Text(verbatim: "\(WalletText.signed(net)) ISK").foregroundStyle(WalletText.color(net))) since \(EVETime.monthDay(first.date))")
                            .font(.hudCaption)
                            .foregroundStyle(Color.hudInkBodyMuted)
                    }
                    if period != .month, let change = model.balanceChange(now: now, period: period) {
                        Text("\(Text(verbatim: "\(WalletText.signed(change)) ISK").foregroundStyle(WalletText.color(change))) in \(WalletText.period(period))")
                            .font(.hudCaption)
                            .foregroundStyle(Color.hudInkBodyMuted)
                    }
                }
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.top, 14)
                if series.count > 1 {
                    HUDBalanceChart(points: series.map { HUDBalanceChart.Point(date: $0.date, value: $0.balance) },
                                    window: now.addingTimeInterval(-period.interval)...now,
                                    valueLabel: { ISK.compact($0) },
                                    startLabel: series.first.map { Text(verbatim: EVETime.monthDay($0.date)) },
                                    endLabel: Text("Today"),
                                    accessibilityLabel: Text("Balance over 30 days"))
                        .padding(.horizontal, HUDMetrics.gutter)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                } else {
                    Spacer().frame(height: 14)
                }
            }
            HUDFreshnessChip(model.source.journal, now: now)
        }
    }
}

/// A category of the period: its total, its share as a bar, how many entries.
private struct WalletCategoryRow: View {
    static let rowStyle = HUDRowStyle(minHeight: 60, verticalPadding: 11)

    let line: WalletCategoryTotal

    var body: some View {
        let isIncome = line.sign == .income
        HStack(spacing: 12) {
            HUDGlyphPlate(systemImage: WalletText.systemImage(line.category))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: WalletText.title(line.category, sign: line.sign))
                        .font(.hudBody)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: WalletText.signed(isIncome ? line.amount : -line.amount))
                        .font(HUDFont.mono(14, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(isIncome ? Color.hudOk : Color.hudInk)
                        .lineLimit(1)
                }
                HUDOrderFillBar(fraction: max(line.share, 0.015),
                                tint: isIncome ? .hudAccent : .hudLineLeader,
                                caption: Text("\(line.share.formatted(.percent.precision(.fractionLength(0)))) · \(line.count) entries"))
            }
        }
        .hudRow(Self.rowStyle)
    }
}
