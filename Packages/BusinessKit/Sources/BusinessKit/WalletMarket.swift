import Foundation

/// One item type's trades.
public struct WalletMarketItem: Sendable, Hashable, Identifiable {
    public var typeID: Int64
    public var soldQuantity: Int64
    public var soldValue: Double
    public var boughtQuantity: Int64
    public var boughtValue: Double
    /// Sales tax paid on this type's sales, unsigned.
    public var salesTax: Double

    public var id: Int64 { typeID }
    public var averageSell: Double? { soldQuantity > 0 ? soldValue / Double(soldQuantity) : nil }
    public var averageBuy: Double? { boughtQuantity > 0 ? boughtValue / Double(boughtQuantity) : nil }
    /// (sell - buy) / buy, as a fraction; nil unless both sides traded.
    public var spread: Double? {
        guard let s = averageSell, let b = averageBuy, b > 0 else { return nil }
        return (s - b) / b
    }
    /// Sold minus bought value.
    public var netFlow: Double { soldValue - boughtValue }
    /// Units that were both bought and sold.
    public var matchedUnits: Int64 { min(soldQuantity, boughtQuantity) }
    /// `(avgSell - avgBuy) * matched` less the share of the sales tax that falls on the matched units;
    /// nil when nothing is matched.
    public var estimatedProfit: Double? {
        guard matchedUnits > 0, let s = averageSell, let b = averageBuy else { return nil }
        return (s - b) * Double(matchedUnits) - salesTax * Double(matchedUnits) / Double(soldQuantity)
    }
}

public struct WalletMarketSummary: Sendable, Hashable {
    /// Largest turnover (sold plus bought) first.
    public var items: [WalletMarketItem]
    public var soldValue: Double
    public var boughtValue: Double
    /// `transaction_tax` and `brokers_fee` from the journal, unsigned.
    public var fees: Double
    public var tradeCount: Int
    public var unitCount: Int64

    /// `journal` supplies the fees and the sales tax. Both inputs are limited to `from...now`.
    public init(transactions: [WalletTransaction], journal: [WalletJournalEntry],
                from: Date = .distantPast, now: Date = .distantFuture) {
        let trades = transactions.filter { $0.date >= from && $0.date <= now }
        let entries = journal.filter { $0.date >= from && $0.date <= now }
        let taxOfSale = absorbedTaxes(in: entries)
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // A corporation trade may have no journal entry; its tax still names the transaction.
        let taxOfTransaction = Dictionary(
            entries.compactMap { e -> (Int64, WalletJournalEntry)? in
                guard e.refType == "transaction_tax", e.contextIDType == "market_transaction_id",
                      let c = e.contextID else { return nil }
                return (c, e)
            },
            uniquingKeysWith: { a, _ in a })

        var items: [Int64: WalletMarketItem] = [:]
        for t in trades {
            var i = items[t.typeID] ?? WalletMarketItem(typeID: t.typeID, soldQuantity: 0, soldValue: 0,
                                                        boughtQuantity: 0, boughtValue: 0, salesTax: 0)
            if t.isBuy {
                i.boughtQuantity += t.quantity
                i.boughtValue += t.value
            } else {
                i.soldQuantity += t.quantity
                i.soldValue += t.value
                if let ref = t.journalRefID, let sale = byID[ref], let tax = taxOfSale[sale.id] {
                    i.salesTax += abs(tax.amount ?? 0)
                } else if let tax = taxOfTransaction[t.id] {
                    i.salesTax += abs(tax.amount ?? 0)
                }
            }
            items[t.typeID] = i
        }
        self.items = items.values.sorted {
            let a = $0.soldValue + $0.boughtValue, b = $1.soldValue + $1.boughtValue
            return a != b ? a > b : $0.typeID < $1.typeID
        }
        soldValue = items.values.reduce(0) { $0 + $1.soldValue }
        boughtValue = items.values.reduce(0) { $0 + $1.boughtValue }
        fees = entries.filter { $0.refType == "transaction_tax" || $0.refType == "brokers_fee" }
            .reduce(0) { $0 + abs($1.amount ?? 0) }
        tradeCount = trades.count
        unitCount = trades.reduce(0) { $0 + $1.quantity }
    }
}
