import BusinessKit
import SwiftUI

/// Every journal entry of 30 days, newest first and by UTC day, filtered to one category from
/// the toolbar. A ratting session's bounty payouts fold into one row that opens in place; a sale
/// carries its sales tax.
struct WalletJournalView: View {
    let model: WalletModel

    @State private var category: WalletCategory?

    init(model: WalletModel, category: WalletCategory?) {
        self.model = model
        _category = State(initialValue: category)
    }

    var body: some View {
        WalletScreen(model: model) { now in
            WalletJournalList(model: model, category: category, now: now)
        }
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(Text(verbatim: category.map(WalletText.title) ?? model.title))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Category", selection: $category) {
                        Text("All Categories").tag(WalletCategory?.none)
                        ForEach(categories, id: \.self) { category in
                            Label(WalletText.title(category), systemImage: WalletText.systemImage(category))
                                .tag(WalletCategory?.some(category))
                        }
                    }
                } label: {
                    Label("Filter by Category", systemImage: category == nil
                          ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }

    /// The categories the journal has, and the chosen one.
    private var categories: [WalletCategory] {
        let present = Set(model.entries.map(\.category)).union(category.map { [$0] } ?? [])
        return WalletCategory.allCases.filter(present.contains)
    }
}

private struct WalletJournalList: View {
    let model: WalletModel
    let category: WalletCategory?
    let now: Date

    @State private var expanded: Set<String> = []

    /// A card row: a journal row, or one payout of an opened bounty session.
    private enum Line: Identifiable {
        case row(WalletJournalRow)
        case payout(WalletJournalEntry)

        var id: String {
            switch self {
            case let .row(row): row.id
            case let .payout(entry): "p\(entry.id)"
            }
        }
    }

    var body: some View {
        let days = model.days(category: category)
        HUDList {
            if days.isEmpty {
                Section {
                    HUDEmptyPanel(title: Text("Nothing in 30 Days"),
                                  message: Text("No entries of this kind in the last 30 days."))
                        .hudBareRow()
                }
            }
            ForEach(days) { day in
                HUDListSection(lines(of: day), row: { line in
                    switch line {
                    case let .row(row): rowView(row)
                    case let .payout(entry): WalletPayoutRow(entry: entry)
                    }
                }, header: {
                    HUDSectionHeader(Text(verbatim: WalletText.day(day.date, now: now))) {
                        Text(verbatim: WalletText.signed(day.net))
                            .foregroundStyle(WalletText.color(day.net))
                    }
                })
            }
            Section {
                HUDFootnote("Bounty payouts of one ratting session fold into one row; a sale carries its sales tax. The figure under the amount is the balance after the entry. EVE keeps 30 days.")
                    .hudBareRow()
            }
        }
    }

    private func lines(of day: WalletJournalDay) -> [Line] {
        day.rows.flatMap { row -> [Line] in
            if case let .bountySession(entries) = row, expanded.contains(row.id) {
                return [.row(row)] + entries.map(Line.payout)
            }
            return [.row(row)]
        }
    }

    @ViewBuilder
    private func rowView(_ row: WalletJournalRow) -> some View {
        switch row {
        case let .entry(entry, tax):
            NavigationLink(value: WalletRoute(division: model.source.division, page: .entry(entry.id))) {
                WalletEntryRow(model: model, entry: entry, tax: tax)
            }
            .hudRowButton(WalletEntryRow.rowStyle)
        case let .bountySession(entries):
            let isOpen = expanded.contains(row.id)
            Button {
                if isOpen { expanded.remove(row.id) } else { expanded.insert(row.id) }
            } label: {
                WalletSessionRow(entries: entries, isOpen: isOpen)
            }
            .hudRowButton(WalletEntryRow.rowStyle)
            .accessibilityHint(isOpen ? Text("Hides the payouts") : Text("Shows the payouts"))
        }
    }
}

/// One journal entry: what it was, with whom and when, the signed amount and the balance after.
struct WalletEntryRow: View {
    static let rowStyle = HUDRowStyle(minHeight: 60, verticalPadding: 10)

    let model: WalletModel
    let entry: WalletJournalEntry
    var tax: WalletJournalEntry?

    var body: some View {
        let amount = entry.amount ?? 0
        HStack(alignment: .top, spacing: 12) {
            HUDGlyphPlate(systemImage: WalletText.systemImage(entry.category))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: model.title(of: entry))
                        .font(.hudBody)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: WalletText.signed(amount))
                        .font(HUDFont.mono(14, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(WalletText.color(amount))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: detail)
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let balance = balanceAfter {
                        Text(verbatim: ISK.compact(balance))
                            .font(.hudMicro)
                            .foregroundStyle(Color.hudInkMuted)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                if let tax, let taxAmount = tax.amount {
                    Text("Sales tax \(WalletText.signed(taxAmount)) · net \(WalletText.signed(amount + taxAmount))")
                        .font(.hudMicro)
                        .tracking(0.5)
                        .foregroundStyle(Color.hudInkBodyMuted)
                        .lineLimit(1)
                }
            }
        }
        .hudRow(Self.rowStyle)
    }

    /// The balance after the later of the sale and its tax.
    private var balanceAfter: Double? {
        guard let tax, tax.id > entry.id else { return entry.balance }
        return tax.balance ?? entry.balance
    }

    /// `×1 @ 9 250 000 · Orin Vael · 11:47`, or `Mara Kestrel · “Ishtar, fitted” · 18:25`.
    private var detail: String {
        var parts: [String] = []
        if entry.isMarketTransaction, let trade = model.ledger.transaction(for: entry) {
            parts.append(WalletText.trade(quantity: trade.quantity, unitPrice: trade.unitPrice))
            if let client = model.name(trade.clientID) { parts.append(client) }
        } else {
            if let party = model.name(model.counterparty(entry)) { parts.append(party) }
            if let reason = entry.reason { parts.append("“\(reason)”") }
        }
        parts.append(EVETime.time(entry.date))
        return parts.joined(separator: " · ")
    }
}

/// A ratting session folded into one row: the payouts' sum, their span and the tax withheld.
private struct WalletSessionRow: View {
    let entries: [WalletJournalEntry]
    let isOpen: Bool

    var body: some View {
        let sum = entries.reduce(0) { $0 + ($1.amount ?? 0) }
        let tax = entries.reduce(0) { $0 + abs($1.tax ?? 0) }
        HStack(alignment: .top, spacing: 12) {
            HUDGlyphPlate(systemImage: WalletText.systemImage(.bounties))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: WalletText.title(refType: "bounty_prizes"))
                        .font(.hudBody)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: WalletText.signed(sum))
                        .font(HUDFont.mono(14, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(WalletText.color(sum))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: detail(tax: tax))
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let balance = entries.first?.balance {
                        Text(verbatim: ISK.compact(balance))
                            .font(.hudMicro)
                            .foregroundStyle(Color.hudInkMuted)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.hudInkFaint)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .hudRow(WalletEntryRow.rowStyle)
    }

    /// `6 payouts · 18:40–20:20 · tax 1.02M`.
    private func detail(tax: Double) -> String {
        let span = "\(EVETime.time(entries.last?.date ?? .now))–\(EVETime.time(entries.first?.date ?? .now))"
        var parts = [String(localized: "\(entries.count) payouts"), span]
        if tax > 0 { parts.append(String(localized: "tax \(ISK.compact(tax))")) }
        return parts.joined(separator: " · ")
    }
}

/// One payout of an opened session.
private struct WalletPayoutRow: View {
    let entry: WalletJournalEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: EVETime.time(entry.date))
                .foregroundStyle(Color.hudInkMuted)
            Spacer(minLength: 8)
            if let tax = entry.tax, tax != 0 {
                Text("Tax \(ISK.priceFigure(abs(tax)))")
                    .foregroundStyle(Color.hudInkMuted)
            }
            Text(verbatim: WalletText.signed(entry.amount ?? 0))
                .foregroundStyle(WalletText.color(entry.amount ?? 0))
        }
        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
        .lineLimit(1)
        .padding(.leading, 48)
        .accessibilityElement(children: .combine)
        .hudRow(HUDRowStyle(background: .hudSurfaceRaised, minHeight: 0, verticalPadding: 7))
    }
}
