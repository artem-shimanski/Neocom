import BusinessKit
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_792_238_400) // 2026-10-17 12:00 UTC
private let minute: TimeInterval = 60
private let day: TimeInterval = 86_400

private func entry(_ id: Int64, _ ref: String, _ amount: Double?, ago: TimeInterval = 0, balance: Double? = nil,
                   first: Int64? = nil, second: Int64? = nil, ctx: Int64? = nil, ctxType: String? = nil,
                   reason: String? = nil) -> WalletJournalEntry {
    WalletJournalEntry(id: id, date: now.addingTimeInterval(-ago), refType: ref, amount: amount, balance: balance,
                       firstPartyID: first, secondPartyID: second, contextID: ctx, contextIDType: ctxType,
                       reason: reason)
}

private func trade(_ id: Int64, type: Int64 = 34, qty: Int64, price: Double, buy: Bool, ref: Int64? = nil,
                   ago: TimeInterval = 0) -> WalletTransaction {
    WalletTransaction(id: id, date: now.addingTimeInterval(-ago), typeID: type, quantity: qty, unitPrice: price,
                      clientID: 1, locationID: 2, isBuy: buy, journalRefID: ref)
}

@Suite struct WalletCategoryTests {
    @Test func representativeRefTypes() {
        let cases: [(String, WalletCategory)] = [
            ("bounty_prizes", .bounties), ("bounty_prize", .bounties), ("ess_escrow_transfer", .bounties),
            ("agent_mission_reward", .missions), ("agent_mission_collateral_paid", .missions),
            ("market_transaction", .market), ("market_escrow", .market),
            ("transaction_tax", .taxesAndFees), ("brokers_fee", .taxesAndFees),
            ("contract_sales_tax", .taxesAndFees), ("contract_price", .contracts),
            ("contract_reward", .contracts), ("contract_collateral", .contracts),
            ("contract_brokers_fee_corp", .taxesAndFees), ("industry_job_tax", .industry),
            ("researching_material_productivity", .industry), ("planetary_export_tax", .planetary),
            ("player_donation", .transfers), ("corporation_account_withdrawal", .transfers),
            ("bounty_prize_corporation_tax", .corporateTaxes),
            ("agent_mission_reward_corporation_tax", .corporateTaxes),
            ("corporate_reward_tax", .corporateTaxes), ("office_rental_fee", .officeAndUpkeep),
            ("jump_clone_activation_fee", .other), ("something_new", .other),
        ]
        for (ref, category) in cases {
            #expect(WalletCategory(refType: ref) == category, "\(ref)")
        }
    }
}

@Suite struct WalletSummaryTests {
    @Test func totalsAndShares() {
        let entries = [
            entry(1, "bounty_prizes", 300, ago: 1 * 3600),
            entry(2, "agent_mission_reward", 100, ago: 2 * 3600),
            entry(3, "market_transaction", 50, ago: 3 * 3600),
            entry(4, "market_transaction", -200, ago: 4 * 3600),
            entry(5, "transaction_tax", -50, ago: 5 * 3600),
            entry(6, "bounty_prizes", 1000, ago: 2 * day),
            entry(7, "player_donation", nil, ago: 1 * 3600),
        ]
        let s = WalletSummary(entries: entries, now: now, period: .day)
        #expect(s.income == 450)
        #expect(s.expenses == 250)
        #expect(s.net == 200)
        #expect(s.incomeByCategory.map(\.category) == [.bounties, .missions, .market])
        #expect(s.incomeByCategory[0].share == 300.0 / 450)
        #expect(s.expensesByCategory.map(\.category) == [.market, .taxesAndFees])
        #expect(s.expensesByCategory[0].count == 1)
        #expect(WalletSummary(entries: entries, now: now, period: .week).income == 1450)
    }
}

@Suite struct WalletBalanceTests {
    @Test func seriesStartsBeforeOldestEntry() {
        let entries = [
            entry(1, "bounty_prizes", 100, ago: 2 * day, balance: 1100),
            entry(2, "market_transaction", -50, ago: 1 * day, balance: 1050),
            entry(3, "player_donation", 10, ago: 1 * day, balance: nil),
            entry(4, "bounty_prizes", 5, ago: 40 * day, balance: 7),
        ]
        let p = WalletBalancePoint.series(from: entries, now: now)
        #expect(p.map(\.balance) == [1000, 1100, 1050, 1050])
        #expect(p.first?.date == now.addingTimeInterval(-30 * day))
        #expect(p.last?.date == now)
    }

    @Test func entryAfterNowIsKept() {
        let entries = [entry(1, "bounty_prizes", 100, ago: -30, balance: 1100)]
        let p = WalletBalancePoint.series(from: entries, now: now)
        #expect(p.last?.date == now.addingTimeInterval(30))
        #expect(p.last?.balance == 1100)
        #expect(WalletSummary(entries: entries, now: now, period: .day).income == 100)
    }

    @Test func emptyIsEmpty() {
        #expect(WalletBalancePoint.series(from: [], now: now).isEmpty)
        #expect(WalletBalancePoint.series(from: [entry(1, "x", 1)], now: now).isEmpty)
    }
}

@Suite struct WalletJournalRowTests {
    private func bounty(_ id: Int64, ago: TimeInterval) -> WalletJournalEntry { entry(id, "bounty_prizes", 10, ago: ago) }

    @Test func sessionBoundaryIsTwentyMinutes() {
        let rows = WalletJournalRow.rows(from: [bounty(1, ago: 60 * minute), bounty(2, ago: 40 * minute), bounty(3, ago: 19 * minute),
                                                bounty(4, ago: 0)])
        #expect(rows.count == 2)
        guard case .bountySession(let first) = rows[0], case .bountySession(let second) = rows[1] else {
            Issue.record("expected sessions")
            return
        }
        #expect(first.map(\.id) == [4, 3])
        #expect(second.map(\.id) == [2, 1])
    }

    @Test func gapOverTwentyMinutesSplits() {
        let rows = WalletJournalRow.rows(from: [bounty(1, ago: 41 * minute), bounty(2, ago: 20 * minute), bounty(3, ago: 0)])
        #expect(rows.count == 2)
        guard case .bountySession(let s) = rows[0], case .entry(let e, _) = rows[1] else {
            Issue.record("unexpected rows")
            return
        }
        #expect(s.map(\.id) == [3, 2])
        #expect(e.id == 1)
    }

    @Test func dayChangeSplitsSession() {
        let midnight = Date(timeIntervalSince1970: 1_792_195_200) // 2026-10-17 00:00 UTC
        let a = WalletJournalEntry(id: 1, date: midnight.addingTimeInterval(-5 * minute), refType: "bounty_prizes", amount: 1)
        let b = WalletJournalEntry(id: 2, date: midnight.addingTimeInterval(5 * minute), refType: "bounty_prizes", amount: 1)
        let rows = WalletJournalRow.rows(from: [a, b])
        #expect(rows.count == 2)
        #expect(WalletJournalDay.days(from: rows).count == 2)
    }

    @Test func otherEntryBreaksSession() {
        let rows = WalletJournalRow.rows(from: [bounty(1, ago: 10 * minute), entry(2, "player_donation", 5, ago: 5 * minute),
                                                bounty(3, ago: 0)])
        #expect(rows.count == 3)
    }

    @Test func taxIsAbsorbedByContext() {
        let entries = [
            entry(1, "market_transaction", 1000, ago: 10, ctx: 77, ctxType: "market_transaction_id"),
            entry(2, "transaction_tax", -45, ago: 0, ctx: 77, ctxType: "market_transaction_id"),
            entry(3, "market_transaction", 500, ago: 20, ctx: 78, ctxType: "market_transaction_id"),
        ]
        let rows = WalletJournalRow.rows(from: entries)
        #expect(rows.count == 2)
        guard case .entry(let sale, let tax) = rows[0] else {
            Issue.record("expected entry")
            return
        }
        #expect(sale.id == 1)
        #expect(tax?.id == 2)
        #expect(rows[0].net == 955)
        guard case .entry(_, let none) = rows[1] else { return }
        #expect(none == nil)
    }

    @Test func taxFallsBackToSameSecond() {
        let entries = [
            entry(1, "market_transaction", 1000, ago: 100),
            entry(2, "transaction_tax", -45, ago: 100),
            entry(3, "market_transaction", 500, ago: 50),
            entry(4, "transaction_tax", -20, ago: 40),
        ]
        let rows = WalletJournalRow.rows(from: entries)
        #expect(rows.count == 3)
    }

    @Test func filterShowsAbsorbedTaxOnItsOwn() {
        let entries = [
            entry(1, "market_transaction", 1000, ago: 10, ctx: 77, ctxType: "market_transaction_id"),
            entry(2, "transaction_tax", -45, ago: 0, ctx: 77, ctxType: "market_transaction_id"),
        ]
        let taxes = WalletJournalRow.rows(from: entries, category: .taxesAndFees)
        #expect(taxes.count == 1)
        #expect(taxes[0].entries.map(\.id) == [2])
        #expect(WalletJournalRow.rows(from: entries, category: .market)[0].entries.map(\.id) == [1])
    }

    @Test func daysSumNets() {
        let rows = WalletJournalRow.rows(from: [entry(1, "player_donation", 100, ago: 0),
                                                entry(2, "player_donation", -30, ago: 1 * minute),
                                                entry(3, "player_donation", 7, ago: 2 * day)])
        let days = WalletJournalDay.days(from: rows)
        #expect(days.count == 2)
        #expect(days[0].net == 70)
        #expect(days[1].net == 7)
    }
}

@Suite struct WalletMarketTests {
    @Test func aggregationAndProfit() {
        let journal = [
            entry(10, "market_transaction", 1500, ago: 10, ctx: 2, ctxType: "market_transaction_id"),
            entry(11, "transaction_tax", -60, ago: 10, ctx: 2, ctxType: "market_transaction_id"),
            entry(12, "brokers_fee", -40, ago: 20),
            entry(13, "market_transaction", 1000, ago: 5, ctx: 3, ctxType: "market_transaction_id"),
            entry(14, "transaction_tax", -40, ago: 5, ctx: 3, ctxType: "market_transaction_id"),
        ]
        let trades = [
            trade(1, qty: 100, price: 8, buy: true, ago: 100),
            trade(2, qty: 100, price: 15, buy: false, ref: 10, ago: 10),
            trade(3, qty: 50, price: 20, buy: false, ref: 13, ago: 5),
            trade(4, type: 35, qty: 5, price: 10, buy: true),
        ]
        let m = WalletMarketSummary(transactions: trades, journal: journal)
        #expect(m.fees == 140)
        #expect(m.soldValue == 2500)
        #expect(m.boughtValue == 850)
        #expect(m.tradeCount == 4)
        #expect(m.unitCount == 255)
        let tritanium = m.items.first { $0.typeID == 34 }!
        #expect(tritanium.soldQuantity == 150)
        #expect(tritanium.averageSell == 2500.0 / 150)
        #expect(tritanium.averageBuy == 8)
        #expect(tritanium.matchedUnits == 100)
        #expect(tritanium.salesTax == 100)
        let expected = (2500.0 / 150 - 8) * 100 - 100 * 100.0 / 150
        #expect(abs(tritanium.estimatedProfit! - expected) < 1e-9)
        #expect(abs((tritanium.spread ?? 0) - ((2500.0 / 150 - 8) / 8)) < 1e-9)
        #expect(m.items.last?.typeID == 35)
        #expect(m.items.last?.estimatedProfit == nil)
    }

    @Test func taxOfTradeWithoutJournalEntry() {
        let journal = [entry(11, "transaction_tax", -30, ctx: 7, ctxType: "market_transaction_id")]
        let m = WalletMarketSummary(transactions: [trade(7, qty: 10, price: 100, buy: false, ref: -1)], journal: journal)
        #expect(m.items.first?.salesTax == 30)
    }

    @Test func transactionSigns() {
        #expect(trade(1, qty: 2, price: 5, buy: true).total == -10)
        #expect(trade(1, qty: 2, price: 5, buy: false).total == 10)
        #expect(trade(1, qty: 2, price: 5, buy: false, ref: -1).journalRefID == nil)
    }

    @Test func ledgerJoin() {
        let sale = entry(10, "market_transaction", 100, ctx: 5, ctxType: "market_transaction_id")
        let t = trade(5, qty: 1, price: 100, buy: false, ref: 10)
        let ledger = WalletLedger(journal: [sale], transactions: [t])
        #expect(ledger.entry(for: t) == sale)
        #expect(ledger.transaction(for: sale) == t)
        let orphan = trade(6, qty: 1, price: 1, buy: true, ref: nil)
        #expect(WalletLedger(journal: [sale], transactions: [orphan]).entry(for: orphan) == nil)
    }
}

@Suite struct WalletMemberTaxTests {
    private let corp: Int64 = 98_000_001

    private let m0: Int64 = 90_000_500
    private let m1: Int64 = 90_000_501
    private let m2: Int64 = 2_112_000_502

    @Test func membersAndWithdrawals() {
        let journal = [
            entry(1, "bounty_prize_corporation_tax", 600, ago: 1 * 3600, first: m0, second: corp),
            entry(2, "bounty_prize_corporation_tax", 200, ago: 2 * 3600, first: corp, second: m0),
            entry(3, "agent_mission_reward_corporation_tax", 200, ago: 1 * day + 3600, first: m0, second: corp),
            entry(4, "bounty_prize_corporation_tax", 400, ago: 3 * 3600, first: corp, second: m1),
            entry(5, "bounty_prize_corporation_tax", 999, ago: 10 * day, first: corp, second: m2),
            entry(6, "corporation_account_withdrawal", -5000, ago: 3600, first: m1, second: corp, reason: "ops"),
            entry(7, "player_donation", 1, ago: 0, first: 9, second: corp),
        ]
        let r = WalletMemberTaxes(journal: journal, corporationID: corp, now: now, period: .week)
        #expect(r.total == 1400)
        #expect(r.members.map(\.memberID) == [m0, m1])
        let m = r.members[0]
        #expect(m.total == 1000)
        #expect(m.bounties == 800)
        #expect(m.other == 200)
        #expect(m.daysActive == 2)
        #expect(m.share == 1000.0 / 1400)
        #expect(m.lastDate == now.addingTimeInterval(-3600))
        #expect(r.withdrawals.count == 1)
        #expect(r.withdrawals[0].whoID == m1)
        #expect(r.withdrawals[0].amount == 5000)
        #expect(r.withdrawals[0].reason == "ops")
        #expect(r.withdrawn == 5000)
        let month = WalletMemberTaxes(journal: journal, corporationID: corp, now: now, period: .month)
        #expect(month.members.count == 3)
    }

    @Test func plainRewardRefTypesCountAsMemberTaxes() {
        let journal = [
            entry(1, "bounty_prizes", 300, ago: 60, first: m0, second: corp),
            entry(2, "ess_escrow_transfer", 100, ago: 60, first: corp, second: m0),
            entry(3, "agent_mission_reward", 50, ago: 60, first: m0, second: corp),
            entry(4, "bounty_prizes", 70, ago: 60, first: 1_000_125, second: corp),
        ]
        let r = WalletMemberTaxes(journal: journal, corporationID: corp, now: now, period: .day)
        #expect(r.members.map(\.memberID) == [m0])
        #expect(r.total == 450)
        #expect(r.members[0].bounties == 400)
        #expect(r.members[0].other == 50)
    }

    @Test func npcPartyIsNotAMember() {
        let concord: Int64 = 1_000_125
        let journal = [
            entry(1, "bounty_prize_corporation_tax", 300, ago: 60, first: concord, second: corp),
            entry(2, "bounty_prize_corporation_tax", 100, ago: 60, first: m0, second: concord),
            entry(3, "agent_mission_reward_corporation_tax", 50, ago: 60, first: 3_008_416, second: corp),
        ]
        let r = WalletMemberTaxes(journal: journal, corporationID: corp, now: now, period: .day)
        #expect(r.members.map(\.memberID) == [m0])
        #expect(r.total == 100)
    }
}
