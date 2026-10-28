import Foundation

/// What one corporation member paid in taxes.
public struct WalletMemberTax: Sendable, Hashable, Identifiable {
    public var memberID: Int64
    public var total: Double
    /// The part from bounty taxes; the rest of `total` is missions and everything else.
    public var bounties: Double
    public var other: Double { total - bounties }
    public var count: Int
    /// Distinct UTC days with a payment.
    public var daysActive: Int
    public var lastDate: Date
    /// Of the period's total.
    public var share: Double

    public var id: Int64 { memberID }
}

/// A `corporation_account_withdrawal`.
public struct WalletWithdrawal: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var date: Date
    /// The character party.
    public var whoID: Int64?
    public var reason: String?
    /// Unsigned.
    public var amount: Double
}

public struct WalletMemberTaxes: Sendable, Hashable {
    /// Largest payer first.
    public var members: [WalletMemberTax]
    public var total: Double
    /// Newest first.
    public var withdrawals: [WalletWithdrawal]
    public var withdrawn: Double

    private static let memberRewardRefTypes: Set<String> = [
        "bounty_prizes", "bounty_prize", "ess_escrow_transfer", "agent_mission_reward",
        "agent_mission_time_bonus_reward",
    ]

    /// From a corporation wallet journal. The member is the party that is neither the corporation nor an NPC
    /// (the second party when both qualify); member taxes are the `*_corporation_tax` ref types,
    /// `corporate_reward_tax` and the plain bounty and mission ref types, which a corporation never earns itself.
    public init(journal: [WalletJournalEntry], corporationID: Int64, now: Date, period: WalletPeriod) {
        let from = now.addingTimeInterval(-period.interval)
        let window = journal.filter { $0.date >= from }

        // Below 90 000 000 are NPC corporations, agents, factions and locations, never a player.
        func isMember(_ id: Int64?) -> Bool {
            guard let id else { return false }
            return id != corporationID && id >= 90_000_000
        }
        func counterparty(_ e: WalletJournalEntry) -> Int64? {
            if isMember(e.secondPartyID) { return e.secondPartyID }
            return isMember(e.firstPartyID) ? e.firstPartyID : nil
        }

        func isMemberTax(_ e: WalletJournalEntry) -> Bool {
            e.category == .corporateTaxes || Self.memberRewardRefTypes.contains(e.refType)
        }
        func isBounty(_ refType: String) -> Bool {
            refType.hasPrefix("bounty_") || refType == "ess_escrow_transfer"
        }

        struct Acc {
            var total = 0.0
            var bounties = 0.0
            var count = 0
            var days = Set<Date>()
            var last = Date.distantPast
        }
        var acc: [Int64: Acc] = [:]
        for e in window where isMemberTax(e) {
            guard let amount = e.amount, let member = counterparty(e) else { continue }
            var a = acc[member] ?? Acc()
            a.total += amount
            if isBounty(e.refType) { a.bounties += amount }
            a.count += 1
            a.days.insert(utcCalendar.startOfDay(for: e.date))
            a.last = max(a.last, e.date)
            acc[member] = a
        }
        let total = acc.values.reduce(0) { $0 + $1.total }
        members = acc.map {
            WalletMemberTax(memberID: $0.key, total: $0.value.total, bounties: $0.value.bounties,
                            count: $0.value.count, daysActive: $0.value.days.count, lastDate: $0.value.last,
                            share: total > 0 ? $0.value.total / total : 0)
        }.sorted { $0.total != $1.total ? $0.total > $1.total : $0.memberID < $1.memberID }
        self.total = total

        withdrawals = window.filter { $0.refType == "corporation_account_withdrawal" }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id > $1.id }
            .map { WalletWithdrawal(id: $0.id, date: $0.date, whoID: counterparty($0), reason: $0.reason,
                                    amount: abs($0.amount ?? 0)) }
        withdrawn = withdrawals.reduce(0) { $0 + $1.amount }
    }
}
