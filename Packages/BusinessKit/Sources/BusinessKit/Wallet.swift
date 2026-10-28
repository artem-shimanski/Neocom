import Foundation

// A wallet's journal (`/characters/{id}/wallet/journal`, `/corporations/{id}/wallets/{division}/journal`)
// and market transactions (`.../wallet/transactions`): 30 days of each. Plain data,
// independent of the ESI types.

/// One journal line. Every ISK movement, with the balance after it.
public struct WalletJournalEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64
    public var date: Date
    /// The raw ESI `ref_type`, kept as is so an unknown one survives.
    public var refType: String
    /// Signed: positive is income.
    public var amount: Double?
    /// The balance after this entry.
    public var balance: Double?
    public var firstPartyID: Int64?
    public var secondPartyID: Int64?
    public var contextID: Int64?
    public var contextIDType: String?
    public var description: String
    public var reason: String?
    public var tax: Double?
    public var taxReceiverID: Int64?

    public init(id: Int64, date: Date, refType: String, amount: Double? = nil, balance: Double? = nil,
                firstPartyID: Int64? = nil, secondPartyID: Int64? = nil, contextID: Int64? = nil,
                contextIDType: String? = nil, description: String = "", reason: String? = nil,
                tax: Double? = nil, taxReceiverID: Int64? = nil) {
        self.id = id
        self.date = date
        self.refType = refType
        self.amount = amount
        self.balance = balance
        self.firstPartyID = firstPartyID
        self.secondPartyID = secondPartyID
        self.contextID = contextID
        self.contextIDType = contextIDType
        self.description = description
        self.reason = reason
        self.tax = tax
        self.taxReceiverID = taxReceiverID
    }

    public var category: WalletCategory { WalletCategory(refType: refType) }

    /// The entry is the money side of a market trade.
    public var isMarketTransaction: Bool { refType == "market_transaction" }
}

/// One market trade.
public struct WalletTransaction: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64
    public var date: Date
    public var typeID: Int64
    public var quantity: Int64
    public var unitPrice: Double
    public var clientID: Int64
    public var locationID: Int64
    public var isBuy: Bool
    /// Whether a character's trade was for themselves; nil for a corporation wallet.
    public var isPersonal: Bool?
    /// The journal entry of this trade; nil where ESI gives -1.
    public var journalRefID: Int64?

    public init(id: Int64, date: Date, typeID: Int64, quantity: Int64, unitPrice: Double, clientID: Int64,
                locationID: Int64, isBuy: Bool, isPersonal: Bool? = nil, journalRefID: Int64? = nil) {
        self.id = id
        self.date = date
        self.typeID = typeID
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.clientID = clientID
        self.locationID = locationID
        self.isBuy = isBuy
        self.isPersonal = isPersonal
        self.journalRefID = journalRefID == -1 ? nil : journalRefID
    }

    /// Quantity times unit price, unsigned.
    public var value: Double { Double(quantity) * unitPrice }
    /// Signed by the wallet: positive for a sale, negative for a purchase.
    public var total: Double { isBuy ? -value : value }
}

// MARK: - Categories

public enum WalletCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case bounties
    case missions
    case market
    case taxesAndFees
    case industry
    case planetary
    case contracts
    case transfers
    case corporateTaxes
    case officeAndUpkeep
    case other

    /// Maps a raw ESI `ref_type`; an unknown one is `other`.
    public init(refType: String) {
        if let exact = Self.table[refType] {
            self = exact
        } else if refType.hasSuffix("_corporation_tax") {
            self = .corporateTaxes
        } else if refType.hasSuffix("_security_tax") {
            self = .taxesAndFees
        } else if refType.hasPrefix("bounty_") {
            self = .bounties
        } else if refType.hasPrefix("contract_") {
            self = refType.hasSuffix("_fee") || refType.hasSuffix("_tax") ? .taxesAndFees : .contracts
        } else if refType.hasPrefix("agent_mission_") || refType.hasPrefix("mission_") {
            self = .missions
        } else if refType.hasPrefix("researching_") {
            self = .industry
        } else if refType.hasPrefix("planetary_") {
            self = .planetary
        } else if refType.hasPrefix("medal_") || refType.hasPrefix("structure_") || refType.hasPrefix("office_") {
            self = .officeAndUpkeep
        } else {
            self = .other
        }
    }

    private static let table: [String: WalletCategory] = {
        var t: [String: WalletCategory] = [:]
        func add(_ category: WalletCategory, _ refTypes: [String]) {
            for r in refTypes { t[r] = category }
        }
        add(.bounties, ["bounty_prize", "bounty_prizes", "ess_escrow_transfer", "bounty_reimbursement"])
        add(.missions, ["agent_mission_reward", "agent_mission_time_bonus_reward", "mission_reward",
                        "mission_completion", "agents_preward", "agent_mission_collateral_paid",
                        "agent_mission_collateral_refunded", "mission_cost", "mission_expiration"])
        add(.market, ["market_transaction", "market_escrow"])
        add(.taxesAndFees, ["transaction_tax", "brokers_fee", "market_provider_tax", "contract_brokers_fee",
                            "contract_brokers_fee_corp", "contract_sales_tax", "contract_deposit_sales_tax",
                            "reprocessing_tax", "asset_safety_recovery_tax"])
        add(.industry, ["industry_job_tax", "manufacturing", "copying", "reaction", "reverse_engineering",
                        "factory_slot_rental_fee", "datacore_fee"])
        add(.planetary, ["planetary_export_tax", "planetary_import_tax", "planetary_construction"])
        add(.transfers, ["player_donation", "player_trading", "corporation_account_withdrawal",
                         "corporation_payment", "corporation_bulk_payment", "corporation_dividend_payment",
                         "inheritance", "shares"])
        add(.corporateTaxes, ["corporate_reward_tax", "daily_goal_payouts_tax"])
        add(.officeAndUpkeep, ["office_rental_fee", "infrastructure_hub_maintenance", "sovereignity_bill",
                               "alliance_maintainance_fee", "war_fee", "corporation_logo_change_cost",
                               "upkeep_adjustment_fee"])
        return t
    }()
}

public enum WalletSign: String, Codable, Sendable, Hashable {
    case income
    case expense
}

// MARK: - Period summary

/// How far back a summary looks.
public enum WalletPeriod: Int, Codable, Sendable, Hashable, CaseIterable {
    case day = 1
    case week = 7
    case month = 30

    public var interval: TimeInterval { TimeInterval(rawValue) * 86_400 }
}

/// What one category moved in one direction.
public struct WalletCategoryTotal: Sendable, Hashable, Identifiable {
    public var category: WalletCategory
    public var sign: WalletSign
    /// Unsigned.
    public var amount: Double
    public var count: Int
    /// Of the income, or of the expenses, depending on `sign`.
    public var share: Double

    public var id: String { "\(category.rawValue).\(sign.rawValue)" }
}

public struct WalletSummary: Sendable, Hashable {
    public var income: Double
    /// Unsigned.
    public var expenses: Double
    public var net: Double { income - expenses }
    /// Largest first.
    public var incomeByCategory: [WalletCategoryTotal]
    public var expensesByCategory: [WalletCategoryTotal]

    /// Entries from `now - period` on; those without an amount are skipped. Nothing is cut after
    /// `now`, so an entry fetched between two ticks of a minute clock is counted at once.
    public init(entries: [WalletJournalEntry], now: Date, period: WalletPeriod) {
        let from = now.addingTimeInterval(-period.interval)
        var buckets: [String: (WalletCategory, WalletSign, Double, Int)] = [:]
        var income = 0.0
        var expenses = 0.0
        for e in entries where e.date >= from {
            guard let amount = e.amount, amount != 0 else { continue }
            let sign: WalletSign = amount > 0 ? .income : .expense
            if sign == .income { income += amount } else { expenses -= amount }
            let key = "\(e.category.rawValue).\(sign.rawValue)"
            var b = buckets[key] ?? (e.category, sign, 0, 0)
            b.2 += abs(amount)
            b.3 += 1
            buckets[key] = b
        }
        func lines(_ sign: WalletSign, _ total: Double) -> [WalletCategoryTotal] {
            buckets.values.filter { $0.1 == sign }
                .map { WalletCategoryTotal(category: $0.0, sign: sign, amount: $0.2, count: $0.3,
                                           share: total > 0 ? $0.2 / total : 0) }
                .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.category.rawValue < $1.category.rawValue }
        }
        self.income = income
        self.expenses = expenses
        incomeByCategory = lines(.income, income)
        expensesByCategory = lines(.expense, expenses)
    }
}

// MARK: - Balance series

public struct WalletBalancePoint: Sendable, Hashable {
    public var date: Date
    public var balance: Double

    /// A step series over the last `days`: the start balance (oldest entry's balance minus its amount) at the
    /// window start, one point per entry with a balance, and the newest balance repeated at `now` (or at the
    /// newest entry, if that is later). Empty when no entry has a balance.
    public static func series(from entries: [WalletJournalEntry], now: Date, days: Int = 30) -> [WalletBalancePoint] {
        let from = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        let sorted = entries
            .filter { $0.balance != nil && $0.date >= from }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.id < $1.id }
        guard let first = sorted.first, let last = sorted.last else { return [] }
        var points = [WalletBalancePoint(date: from, balance: first.balance! - (first.amount ?? 0))]
        points += sorted.map { WalletBalancePoint(date: $0.date, balance: $0.balance!) }
        points.append(WalletBalancePoint(date: max(now, last.date), balance: last.balance!))
        return points
    }
}

// MARK: - Journal rows

public enum WalletJournalRow: Sendable, Hashable, Identifiable {
    /// An entry; for a sale, with the sales tax of the same trade.
    case entry(WalletJournalEntry, tax: WalletJournalEntry?)
    /// Two or more bounty payouts of one session, newest first.
    case bountySession([WalletJournalEntry])

    public var id: String {
        switch self {
        case .entry(let e, _): "e\(e.id)"
        case .bountySession(let es): "s\(es.last?.id ?? 0)"
        }
    }

    /// Every journal entry the row stands for.
    public var entries: [WalletJournalEntry] {
        switch self {
        case .entry(let e, let tax): tax.map { [e, $0] } ?? [e]
        case .bountySession(let es): es
        }
    }

    public var date: Date { entries[0].date }

    /// Signed sum, a sale's tax included.
    public var net: Double { entries.reduce(0) { $0 + ($1.amount ?? 0) } }

    /// Newest first; a lone bounty tick stays a plain entry. A session is consecutive `bounty_prizes` of one
    /// UTC day, each at most 20 minutes after the previous. `category` filters before folding, so a sale whose
    /// tax is filtered out, or the other way round, shows on its own.
    public static func rows(from entries: [WalletJournalEntry], category: WalletCategory? = nil) -> [WalletJournalRow] {
        let sorted = entries
            .filter { category == nil || $0.category == category }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id > $1.id }
        let taxes = absorbedTaxes(in: sorted)
        let absorbed = Set(taxes.values.map(\.id))

        var rows: [WalletJournalRow] = []
        var session: [WalletJournalEntry] = []
        func flush() {
            if session.count == 1 {
                rows.append(.entry(session[0], tax: nil))
            } else if session.count > 1 {
                rows.append(.bountySession(session))
            }
            session = []
        }
        for e in sorted where !absorbed.contains(e.id) {
            if e.refType == "bounty_prizes" {
                if let last = session.last, !(sameUTCDay(last.date, e.date) && last.date.timeIntervalSince(e.date) <= 20 * 60) {
                    flush()
                }
                session.append(e)
                continue
            }
            flush()
            rows.append(.entry(e, tax: taxes[e.id]))
        }
        flush()
        return rows
    }
}

/// One UTC day of rows.
public struct WalletJournalDay: Sendable, Hashable, Identifiable {
    /// Midnight UTC.
    public var date: Date
    public var rows: [WalletJournalRow]
    public var net: Double { rows.reduce(0) { $0 + $1.net } }
    public var id: Date { date }

    /// Rows already sorted newest first, grouped by UTC day.
    public static func days(from rows: [WalletJournalRow]) -> [WalletJournalDay] {
        var days: [WalletJournalDay] = []
        for row in rows {
            let start = utcCalendar.startOfDay(for: row.date)
            if days.last?.date == start {
                days[days.count - 1].rows.append(row)
            } else {
                days.append(WalletJournalDay(date: start, rows: [row]))
            }
        }
        return days
    }
}

let utcCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func sameUTCDay(_ a: Date, _ b: Date) -> Bool { utcCalendar.isDate(a, inSameDayAs: b) }

/// Sale entry id -> the `transaction_tax` entry of the same trade. Matched by the transaction id in the
/// context of both; a tax without a context falls back to a sale with the same timestamp (to the second).
func absorbedTaxes(in entries: [WalletJournalEntry]) -> [Int64: WalletJournalEntry] {
    let marketType = "market_transaction_id"
    var taxByContext: [Int64: WalletJournalEntry] = [:]
    var bare: [Int64: [WalletJournalEntry]] = [:]
    for t in entries where t.refType == "transaction_tax" {
        if t.contextIDType == marketType, let c = t.contextID {
            taxByContext[c] = taxByContext[c] ?? t
        } else if t.contextID == nil {
            bare[Int64(t.date.timeIntervalSince1970.rounded(.down)), default: []].append(t)
        }
    }
    var result: [Int64: WalletJournalEntry] = [:]
    for s in entries where s.isMarketTransaction && (s.amount ?? 0) > 0 {
        if s.contextIDType == marketType, let c = s.contextID, let t = taxByContext[c] {
            result[s.id] = t
        } else {
            let key = Int64(s.date.timeIntervalSince1970.rounded(.down))
            if var list = bare[key], !list.isEmpty {
                result[s.id] = list.removeFirst()
                bare[key] = list
            }
        }
    }
    return result
}

// MARK: - Journal <-> transactions

/// Looks a trade up from its journal entry and back.
public struct WalletLedger: Sendable {
    private let entriesByID: [Int64: WalletJournalEntry]
    private let transactionsByID: [Int64: WalletTransaction]
    private let transactionsByRef: [Int64: WalletTransaction]

    public init(journal: [WalletJournalEntry], transactions: [WalletTransaction]) {
        entriesByID = Dictionary(journal.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        transactionsByID = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        transactionsByRef = Dictionary(transactions.compactMap { t in t.journalRefID.map { ($0, t) } },
                                       uniquingKeysWith: { a, _ in a })
    }

    public func entry(for transaction: WalletTransaction) -> WalletJournalEntry? {
        transaction.journalRefID.flatMap { entriesByID[$0] }
    }

    public func transaction(for entry: WalletJournalEntry) -> WalletTransaction? {
        if let t = transactionsByRef[entry.id] { return t }
        if entry.isMarketTransaction, entry.contextIDType == "market_transaction_id", let c = entry.contextID {
            return transactionsByID[c]
        }
        return nil
    }
}
