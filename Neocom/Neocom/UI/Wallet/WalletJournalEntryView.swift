import BusinessKit
import SDEKit
import SwiftUI

/// One journal entry: the amount, the facts ESI gives, and for a market trade the transaction it
/// points to and the sales tax booked with it.
struct WalletJournalEntryView: View {
    let model: WalletModel
    let entryID: Int64

    var body: some View {
        WalletScreen(model: model) { _ in
            if let entry = model.entry(id: entryID) {
                WalletEntryDetail(model: model, entry: entry)
            } else {
                HUDList {
                    Section {
                        HUDEmptyPanel(title: Text("Entry Not Found"),
                                      message: Text("The entry is no longer in the last 30 days of the journal."))
                            .hudBareRow()
                    }
                }
            }
        }
        .navigationTitle("Journal Entry")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WalletEntryDetail: View {
    let model: WalletModel
    let entry: WalletJournalEntry

    var body: some View {
        let trade = model.ledger.transaction(for: entry)
        let tax = model.salesTax(of: entry)
        let sale = model.sale(ofTax: entry)
        HUDList {
            Section { header(trade: trade, tax: tax).hudBareRow() }
            journal
            if let trade {
                transaction(trade)
            }
            if let tax {
                sameTrade(tax, title: Text("Sales Tax"))
            } else if let sale {
                sameTrade(sale, title: Text(verbatim: model.title(of: sale)))
            }
            if trade != nil || sale != nil {
                Section {
                    HUDFootnote("The journal holds the ISK. What was traded, how many, at what price and with whom comes from the market transaction it points to. Broker’s fees are paid when an order is placed and are separate entries.")
                        .hudBareRow()
                }
            }
        }
    }

    // MARK: Header

    private func header(trade: WalletTransaction?, tax: WalletJournalEntry?) -> some View {
        let amount = entry.amount ?? 0
        var items: [HUDStatStrip.Item] = [
            .init(id: 0, label: Text("Amount"), value: Text(verbatim: signedFigure(amount)),
                  color: WalletText.color(amount)),
        ]
        if let taxAmount = tax?.amount {
            items.append(.init(id: 1, label: Text("Net of Tax"), value: Text(verbatim: signedFigure(amount + taxAmount)),
                               color: WalletText.color(amount + taxAmount)))
        } else if let balance = entry.balance {
            items.append(.init(id: 1, label: Text("Balance After"), value: Text(verbatim: ISK.compact(balance))))
        }
        return HUDPanel {
            HStack(spacing: 12) {
                HUDGlyphPlate(systemImage: WalletText.systemImage(entry.category), size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: WalletText.title(refType: entry.refType))
                        .font(HUDFont.display(18, weight: .bold, relativeTo: .headline))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .lineLimit(2)
                    Text(verbatim: kind(trade: trade))
                        .font(.hudMicro)
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 14)
            HUDPanelRule()
            HUDStatStrip(items: items)
        }
    }

    /// `Sold · 2026.10.18 05:50 EVE`, or the category and the time.
    private func kind(trade: WalletTransaction?) -> String {
        let side = trade.map { $0.isBuy ? String(localized: "Bought") : String(localized: "Sold") }
            ?? WalletText.title(entry.category)
        return "\(side) · \(String(localized: "\(EVETime.dateTime(entry.date)) EVE"))"
    }

    private func signedFigure(_ value: Double) -> String {
        let figure = abs(value).formatted(.number.precision(.fractionLength(2)))
        return value < 0 ? "−\(figure)" : value > 0 ? "+\(figure)" : figure
    }

    // MARK: Journal

    private var journal: some View {
        HUDListSection(Text("Journal")) {
            HUDReadoutRow("Ref Type", value: entry.refType)
            HUDReadoutRow("Entry", value: "#\(entry.id)")
            if let from = entry.firstPartyID {
                HUDReadoutRow("From", value: model.name(from) ?? "#\(from)")
            }
            if let to = entry.secondPartyID {
                HUDReadoutRow("To", value: model.name(to) ?? "#\(to)")
            }
            if let balance = entry.balance {
                HUDReadoutRow("Balance After", value: ISK.string(balance))
            }
            if let reason = entry.reason {
                HUDReadoutRow("Reason", value: reason)
            }
            if let tax = entry.tax, tax != 0 {
                HUDReadoutRow("Tax", value: ISK.string(abs(tax)))
            }
            if let receiver = entry.taxReceiverID {
                HUDReadoutRow("Tax Receiver", value: model.name(receiver) ?? "#\(receiver)")
            }
            if let context = entry.contextID, let type = entry.contextIDType, !entry.isMarketTransaction {
                HUDReadoutRow("Context", value: contextText(id: context, type: type))
            }
            if !entry.description.isEmpty {
                Text(verbatim: entry.description)
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .lineSpacing(3)
                    .foregroundStyle(Color.hudInkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
            }
        }
    }

    /// A named party for a character, corporation or alliance context; the raw id otherwise.
    private func contextText(id: Int64, type: String) -> String {
        if let name = model.name(id) { return name }
        return "\(type.replacingOccurrences(of: "_", with: " ")) #\(id)"
    }

    // MARK: Market transaction

    private func transaction(_ trade: WalletTransaction) -> some View {
        HUDListSection(content: {
            NavigationLink(value: WalletRoute(division: model.source.division, page: .item(trade.typeID))) {
                HStack(spacing: 12) {
                    HUDItemIcon(typeID: TypeID(rawValue: UInt32(clamping: trade.typeID)), size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: model.typeName(trade.typeID))
                            .font(.hudBody)
                            .lineLimit(1)
                        Text(verbatim: "\(trade.isBuy ? String(localized: "Bought") : String(localized: "Sold")) \(WalletText.trade(quantity: trade.quantity, unitPrice: trade.unitPrice)) ISK")
                            .font(.hudMicro)
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    HUDChevron()
                }
                .hudRow(.subtitled)
            }
            .hudRowButton(.subtitled)
            HUDReadoutRow(trade.isBuy ? Text("Seller") : Text("Buyer"), value: model.name(trade.clientID) ?? "#\(trade.clientID)")
            HUDReadoutRow("Where", value: model.locationName(trade.locationID))
            if let system = model.system(ofLocation: trade.locationID) {
                HUDReadoutRow("System") {
                    HUDPlaceBlock.system(name: system.name, security: system.securityStatus)
                }
            }
            if let isPersonal = trade.isPersonal {
                HUDReadoutRow("Order", value: isPersonal ? String(localized: "Personal") : String(localized: "Corporation"))
            }
            HUDReadoutRow("Time", value: EVETime.dateTime(trade.date))
        }, header: {
            HUDSectionHeader(Text("Market Transaction")) {
                Text(verbatim: "#\(trade.id)")
            }
        })
    }

    // MARK: Same trade

    private func sameTrade(_ other: WalletJournalEntry, title: Text) -> some View {
        let amount = other.amount ?? 0
        return HUDListSection(Text("Same Trade")) {
            NavigationLink(value: WalletRoute(division: model.source.division, page: .entry(other.id))) {
                HStack(spacing: 12) {
                    HUDGlyphPlate(systemImage: WalletText.systemImage(other.category))
                    VStack(alignment: .leading, spacing: 3) {
                        title
                            .font(.hudBody)
                            .lineLimit(1)
                        Text(verbatim: otherDetail(other))
                            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(Color.hudInkMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(verbatim: signedFigure(amount))
                        .font(HUDFont.mono(13, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(WalletText.color(amount))
                        .lineLimit(1)
                    HUDChevron()
                }
                .hudRow(.subtitled)
            }
            .hudRowButton(.subtitled)
        }
    }

    /// `3.60% · SCC · 12:04`: the tax's rate of the sale, who received it, when.
    private func otherDetail(_ other: WalletJournalEntry) -> String {
        var parts: [String] = []
        let (sale, tax) = other.refType == "transaction_tax" ? (entry, other) : (other, entry)
        if let saleAmount = sale.amount, saleAmount != 0, let taxAmount = tax.amount {
            parts.append(abs(taxAmount / saleAmount).formatted(.percent.precision(.fractionLength(2))))
        }
        if let party = model.name(model.counterparty(other)) { parts.append(party) }
        parts.append(EVETime.time(other.date))
        return parts.joined(separator: " · ")
    }
}
