import AssetsKit
import BusinessKit
import LiteRow
import Observation
import SDEKit
import SwiftUI

/// What the Wallet screens read: one wallet's journal and transactions, the names around them,
/// and what BusinessKit makes of them, kept until either list changes.
@Observable
@MainActor
final class WalletModel {
    struct TypeLabel {
        var name: String
        var group: String?
    }

    let source: any WalletSource
    private(set) var types: [Int64: TypeLabel] = [:]
    private(set) var systems: [Int64: MarketSystemRow] = [:]

    @ObservationIgnored let corporation: CorporationSheet?
    @ObservationIgnored private let database: SDEDatabase
    @ObservationIgnored private let market: MarketSheet

    @ObservationIgnored private var memoKey: [Int] = []
    @ObservationIgnored private var memoLedger: WalletLedger?
    @ObservationIgnored private var memoRows: [WalletCategory?: [WalletJournalRow]] = [:]
    @ObservationIgnored private var memoDays: [WalletCategory?: [WalletJournalDay]] = [:]
    @ObservationIgnored private var memoSalesTax: [Int64: WalletJournalEntry]?
    @ObservationIgnored private var memoMarket: WalletMarketSummary?
    @ObservationIgnored private var memoTradeDays: [WalletTradeDay]?
    @ObservationIgnored private var memoSeries: (now: Date, points: [WalletBalancePoint])?
    @ObservationIgnored private var memoSummaries: [WalletPeriod: (now: Date, summary: WalletSummary)] = [:]
    @ObservationIgnored private var memoMemberTaxes: [WalletPeriod: (now: Date, taxes: WalletMemberTaxes)] = [:]

    init(source: any WalletSource, corporation: CorporationSheet?, database: SDEDatabase, market: MarketSheet) {
        self.source = source
        self.corporation = corporation
        self.database = database
        self.market = market
    }

    // MARK: - Reading

    var isCorporation: Bool { source.corporationID != nil }

    /// The wallet's owner: the character, or the corporation.
    var ownerID: Int64 { source.corporationID ?? source.characterID }

    /// `Wallet`, or the corporation's name of the division.
    var title: String {
        guard let division = source.division else { return String(localized: "Wallet") }
        return corporation?.walletName(division) ?? ESICorporationDivisions.walletName(division, in: [:])
    }

    var entries: [WalletJournalEntry] { source.journal.value?.entries ?? [] }
    var transactions: [WalletTransaction] { source.transactions.value?.transactions ?? [] }

    func entry(id: Int64) -> WalletJournalEntry? {
        entries.first { $0.id == id }
    }

    func name(_ id: Int64?) -> String? {
        guard let id else { return nil }
        return source.journal.value?.names[id]?.name ?? source.transactions.value?.names[id]?.name
    }

    /// The party of an entry that is not the wallet's owner.
    func counterparty(_ entry: WalletJournalEntry) -> Int64? {
        let owner = ownerID
        if let first = entry.firstPartyID, first != owner, entry.secondPartyID == owner || entry.secondPartyID == nil {
            return first
        }
        if let second = entry.secondPartyID, second != owner { return second }
        return entry.firstPartyID != owner ? entry.firstPartyID : nil
    }

    func typeName(_ typeID: Int64) -> String {
        types[typeID]?.name ?? "—"
    }

    func locationName(_ locationID: Int64) -> String {
        if let name = source.transactions.value?.locations[locationID]?.name { return name }
        if let name = market.stationNames[locationID] { return name }
        return String(localized: "Unknown Location")
    }

    func system(ofLocation locationID: Int64) -> MarketSystemRow? {
        source.transactions.value?.locations[locationID]?.solarSystemID.flatMap { systems[$0] }
    }

    /// `Sold Vexor`, `Bought Tritanium`, or what the ref type is called.
    func title(of entry: WalletJournalEntry) -> String {
        if entry.isMarketTransaction, let trade = ledger.transaction(for: entry) {
            let name = typeName(trade.typeID)
            return trade.isBuy ? String(localized: "Bought \(name)") : String(localized: "Sold \(name)")
        }
        return WalletText.title(refType: entry.refType)
    }

    // MARK: - Derived

    var ledger: WalletLedger {
        validateMemo()
        if let memoLedger { return memoLedger }
        let ledger = WalletLedger(journal: entries, transactions: transactions)
        memoLedger = ledger
        return ledger
    }

    func rows(category: WalletCategory?) -> [WalletJournalRow] {
        validateMemo()
        if let rows = memoRows[category] { return rows }
        let rows = WalletJournalRow.rows(from: entries, category: category)
        memoRows[category] = rows
        return rows
    }

    /// The journal rows by UTC day, newest first.
    func days(category: WalletCategory?) -> [WalletJournalDay] {
        validateMemo()
        if let days = memoDays[category] { return days }
        let days = WalletJournalDay.days(from: rows(category: category))
        memoDays[category] = days
        return days
    }

    /// The sales tax booked with a sale.
    func salesTax(of entry: WalletJournalEntry) -> WalletJournalEntry? {
        validateMemo()
        if memoSalesTax == nil {
            var taxes: [Int64: WalletJournalEntry] = [:]
            for case let .entry(sale, tax?) in rows(category: nil) {
                taxes[sale.id] = tax
            }
            memoSalesTax = taxes
        }
        return memoSalesTax?[entry.id]
    }

    /// The sale a sales tax was booked with.
    func sale(ofTax entry: WalletJournalEntry) -> WalletJournalEntry? {
        guard entry.refType == "transaction_tax" else { return nil }
        _ = salesTax(of: entry)
        guard let id = memoSalesTax?.first(where: { $0.value.id == entry.id })?.key else { return nil }
        return self.entry(id: id)
    }

    var marketSummary: WalletMarketSummary {
        validateMemo()
        if let memoMarket { return memoMarket }
        let summary = WalletMarketSummary(transactions: transactions, journal: entries)
        memoMarket = summary
        return summary
    }

    /// Trades by UTC day, newest first.
    var tradeDays: [WalletTradeDay] {
        validateMemo()
        if let memoTradeDays { return memoTradeDays }
        let days = WalletTradeDay.days(from: transactions)
        memoTradeDays = days
        return days
    }

    /// The balance over 30 days up to `now`.
    func balanceSeries(now: Date) -> [WalletBalancePoint] {
        validateMemo()
        if let memoSeries, memoSeries.now == now { return memoSeries.points }
        let points = WalletBalancePoint.series(from: entries, now: now)
        memoSeries = (now, points)
        return points
    }

    /// The balance change over `period` up to `now`: the last balance at or before the window start
    /// (the first one if the series starts later) to the newest.
    func balanceChange(now: Date, period: WalletPeriod) -> Double? {
        let series = balanceSeries(now: now)
        guard let first = series.first, let last = series.last else { return nil }
        let from = now.addingTimeInterval(-period.interval)
        let base = series.last { $0.date <= from } ?? first
        return last.balance - base.balance
    }

    func summary(now: Date, period: WalletPeriod) -> WalletSummary {
        validateMemo()
        if let memo = memoSummaries[period], memo.now == now { return memo.summary }
        let summary = WalletSummary(entries: entries, now: now, period: period)
        memoSummaries[period] = (now, summary)
        return summary
    }

    /// The members' taxes and the withdrawals; the wallet is a corporation's Master Wallet.
    func memberTaxes(now: Date, period: WalletPeriod) -> WalletMemberTaxes {
        validateMemo()
        if let memo = memoMemberTaxes[period], memo.now == now { return memo.taxes }
        let taxes = WalletMemberTaxes(journal: entries, corporationID: ownerID, now: now, period: period)
        memoMemberTaxes[period] = (now, taxes)
        return taxes
    }

    private func validateMemo() {
        let key = [source.journal.revision, source.transactions.revision,
                   source.journal.value?.entries.count ?? -1, source.transactions.value?.transactions.count ?? -1]
        guard key != memoKey else { return }
        memoKey = key
        memoLedger = nil
        memoRows = [:]
        memoDays = [:]
        memoSalesTax = nil
        memoMarket = nil
        memoTradeDays = nil
        memoSeries = nil
        memoSummaries = [:]
        memoMemberTaxes = [:]
    }

    // MARK: - Loading

    /// Type and system names for the transactions; local and safe to call on every revision.
    func resolveNames() async {
        let trades = transactions
        guard !trades.isEmpty else { return }
        let locations = source.transactions.value?.locations ?? [:]
        let typeIDs = Set(trades.map(\.typeID)).filter { types[$0] == nil }
            .map { TypeID(rawValue: UInt32(clamping: $0)) }
        let systemIDs = Set(locations.values.compactMap(\.solarSystemID)).filter { systems[$0] == nil }
            .map(MarketFormat.systemID)
        if !(typeIDs.isEmpty && systemIDs.isEmpty) {
            let database = database
            // Unstructured: the caller's task is cancelled whenever a revision lands.
            let read = try? await Task { try await database.database.read { reader -> ([AssetTypeRow], [GroupHeader], [MarketSystemRow]) in
                let typeRows = try stride(from: 0, to: typeIDs.count, by: 500).flatMap {
                    try reader.fetchAll(AssetsBrowser.types(Array(typeIDs[$0..<min($0 + 500, typeIDs.count)])))
                }
                let groupIDs = Array(Set(typeRows.map(\.groupID)))
                let groups = groupIDs.isEmpty ? [] : try reader.fetchAll(AssetsBrowser.groups(groupIDs))
                let systemRows = systemIDs.isEmpty ? [] : try reader.fetchAll(MarketBrowser.systems(systemIDs))
                return (typeRows, groups, systemRows)
            } }.value
            if let (typeRows, groups, systemRows) = read {
                let groupNames = Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
                for row in typeRows {
                    types[Int64(row.id.rawValue)] = TypeLabel(name: row.name, group: groupNames[row.groupID])
                }
                for row in systemRows { systems[Int64(row.id.rawValue)] = row }
            }
        }
        let unnamed = Set(trades.map(\.locationID)).filter { locations[$0]?.name == nil }
        if !unnamed.isEmpty {
            await market.resolveStationNames(unnamed)
        }
    }
}

/// One model per wallet for the screens of a section, so the names are read once.
@MainActor
final class WalletModelStore {
    private var models: [ObjectIdentifier: WalletModel] = [:]

    func model(for source: any WalletSource, corporation: CorporationSheet?, database: SDEDatabase,
               market: MarketSheet) -> WalletModel {
        let key = ObjectIdentifier(source)
        if let model = models[key] { return model }
        let model = WalletModel(source: source, corporation: corporation, database: database, market: market)
        models[key] = model
        return model
    }
}
