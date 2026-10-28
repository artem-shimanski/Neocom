import DemoFixtures
import Foundation

/// The wallet journal and market transactions the demo pilot shows, derived from `DemoConfig.wallet`.
extension DemoExporter {
    static let walletJournalOperation = "GetCharactersCharacterIdWalletJournal"
    static let walletTransactionsOperation = "GetCharactersCharacterIdWalletTransactions"

    /// ESI keeps 30 days; the oldest configured entry stays well inside, so the rebased data does
    /// for a while after the recording.
    public static let walletWindowHours: Double = 28 * 24
    /// The newest configured entry is at least this far before the recording.
    public static let walletMinimumHours: Double = 1

    static let journalIDBase = DemoIDs.syntheticRange.lowerBound + 500_000
    static let transactionIDBase = DemoIDs.syntheticRange.lowerBound + 600_000
    static let concordID: Int64 = 1_000_125
    static let taxReceiverID: Int64 = 1_000_132
    static let tickInterval: Double = 1.0 / 3

    private struct Row {
        var seconds: Int64
        var sequence: Int
        var cents: Int64
        var refType: String
        var firstPartyID: Int64?
        var secondPartyID: Int64?
        var reason: String?
        var description: String
        var contextID: Int64?
        var contextIDType: String?
        var tax: Int64?
        var taxReceiverID: Int64?
        var transactionID: Int64?
    }

    private struct Sale {
        var seconds: Int64
        var id: Int64
        var trade: DemoConfig.Trade
    }

    /// Replaces the wallet of an existing archive with the configured one; nothing else changes.
    /// The new entries go where the exporter's ordering puts them.
    public func applyWallet(to archive: inout DemoArchive) throws {
        try validateSyntheticIDs()
        var entries = archive.entries
        entries.removeAll(where: Self.isWallet)
        for entry in try walletEntries(recordedAt: archive.recordedAt) {
            let key = (entry.path, entry.operationID, entry.query, entry.method)
            let index = entries.firstIndex { key < ($0.path, $0.operationID, $0.query, $0.method) } ?? entries.endIndex
            entries.insert(entry, at: index)
        }
        archive.entries = entries
        for named in config.names {
            archive.names[String(named.id)] = DemoArchive.Name(name: named.name, category: named.category)
        }
    }

    static func isWallet(_ entry: DemoArchive.Entry) -> Bool {
        entry.operationID == walletJournalOperation || entry.operationID == walletTransactionsOperation
    }

    /// Drops every recorded wallet journal and transaction list, then adds the configured ones.
    func applyWallet(to entries: inout [DemoArchive.Entry], recordedAt: Date) throws {
        entries.removeAll(where: Self.isWallet)
        entries.append(contentsOf: try walletEntries(recordedAt: recordedAt))
    }

    private func walletEntries(recordedAt: Date) throws -> [DemoArchive.Entry] {
        var entries: [DemoArchive.Entry] = []
        let wallet = config.wallet
        let pilot = DemoIDs.characterID
        let base = "/characters/\(pilot)/wallet"

        func seconds(_ hoursAgo: Double) throws -> Int64 {
            guard (Self.walletMinimumHours ... Self.walletWindowHours).contains(hoursAgo) else {
                throw DemoExportError.invalidWallet("\(hoursAgo) hours ago is outside \(Self.walletMinimumHours)…\(Self.walletWindowHours)")
            }
            return Int64(recordedAt.addingTimeInterval(-hoursAgo * 3600).timeIntervalSince1970.rounded(.down))
        }
        func cents(_ value: Double) -> Int64 { Int64((value * 100).rounded()) }
        func quantity(_ value: Int64) -> String { value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US"))) }
        func typeName(_ id: Int64) -> String { wallet.types[String(id)] ?? "type \(id)" }

        var rows: [Row] = []
        func add(_ seconds: Int64, _ cents: Int64, _ refType: String, first: Int64?, second: Int64?, description: String,
                 reason: String? = nil, context: Int64? = nil, contextType: String? = nil,
                 tax: Int64? = nil, taxReceiver: Int64? = nil, transaction: Int64? = nil) {
            rows.append(Row(seconds: seconds, sequence: rows.count, cents: cents, refType: refType, firstPartyID: first,
                            secondPartyID: second, reason: reason, description: description, contextID: context,
                            contextIDType: contextType, tax: tax, taxReceiverID: taxReceiver, transactionID: transaction))
        }

        for session in wallet.ratting {
            for (tick, gross) in session.payouts.enumerated() {
                let time = try seconds(session.hoursAgo - Double(tick) * Self.tickInterval)
                let share = cents(gross * wallet.corporationTax)
                add(time, cents(gross) - share, "bounty_prizes", first: Self.concordID, second: pilot,
                    description: "Bounty prizes in \(session.systemName)", context: session.systemID,
                    contextType: "system_id", tax: share, taxReceiver: config.pilot.corporationID)
            }
            if let payout = session.essPayout {
                let last = session.hoursAgo - Double(session.payouts.count - 1) * Self.tickInterval
                add(try seconds(last - 0.15), cents(payout), "ess_escrow_transfer", first: Self.concordID, second: pilot,
                    description: "ESS payout")
            }
        }

        let sorted = try wallet.trades.map { (seconds: try seconds($0.hoursAgo), trade: $0) }
            .enumerated().sorted { ($0.element.seconds, $0.offset) < ($1.element.seconds, $1.offset) }
        var transactions: [Sale] = []
        for (rank, element) in sorted.enumerated() {
            let (time, trade) = (element.element.seconds, element.element.trade)
            let id = Self.transactionIDBase + Int64(rank) + 1
            transactions.append(Sale(seconds: time, id: id, trade: trade))
            let gross = Int64((Double(trade.quantity) * trade.unitPrice * 100).rounded())
            let item = "\(quantity(trade.quantity)) x \(typeName(trade.typeID))"
            if trade.isBuy {
                add(time, -gross, "market_transaction", first: pilot, second: trade.clientID,
                    description: "Market: bought \(item)", context: id, contextType: "market_transaction_id", transaction: id)
            } else {
                add(time, gross, "market_transaction", first: trade.clientID, second: pilot,
                    description: "Market: sold \(item)", context: id, contextType: "market_transaction_id", transaction: id)
                add(time, -Int64((Double(gross) * wallet.salesTax).rounded()), "transaction_tax", first: pilot,
                    second: Self.taxReceiverID, description: "Transaction tax for \(item)", context: id,
                    contextType: "market_transaction_id")
            }
        }

        for entry in wallet.entries {
            add(try seconds(entry.hoursAgo), cents(entry.amount), entry.refType, first: entry.firstPartyID,
                second: entry.secondPartyID, description: entry.description ?? Self.walletDescription(entry),
                reason: entry.reason, context: entry.contextID, contextType: entry.contextIDType)
        }

        rows.sort { ($0.seconds, $0.sequence) < ($1.seconds, $1.sequence) }
        guard rows.count < 100_000 else { throw DemoExportError.invalidWallet("too many entries") }
        let parties = Set(rows.flatMap { [$0.firstPartyID, $0.secondPartyID].compactMap(\.self) })
        if let id = parties.first(where: { $0 != pilot && !DemoIDs.contains($0) && !Self.npcCorporations.contains($0) }) {
            throw DemoExportError.notSynthetic(id)
        }
        if let id = wallet.trades.map(\.clientID).first(where: { !DemoIDs.contains($0) }) {
            throw DemoExportError.notSynthetic(id)
        }

        var journalIDs: [Int64: Int64] = [:]
        var balance = cents(config.pilot.walletBalance)
        var journal: [DemoJSON] = []
        for (index, row) in rows.enumerated().reversed() {
            guard balance >= 0 else {
                throw DemoExportError.invalidWallet("the balance is negative before \(DemoRebaser.timestamp(Date(timeIntervalSince1970: TimeInterval(row.seconds))))")
            }
            let id = Self.journalIDBase + Int64(index) + 1
            if let transaction = row.transactionID { journalIDs[transaction] = id }
            var object: [String: DemoJSON] = [
                "id": .int(id), "date": .string(DemoRebaser.timestamp(Date(timeIntervalSince1970: TimeInterval(row.seconds)))),
                "ref_type": .string(row.refType), "description": .string(row.description),
                "amount": .double(Double(row.cents) / 100), "balance": .double(Double(balance) / 100),
            ]
            object["first_party_id"] = row.firstPartyID.map(DemoJSON.int)
            object["second_party_id"] = row.secondPartyID.map(DemoJSON.int)
            object["reason"] = row.reason.map(DemoJSON.string)
            object["context_id"] = row.contextID.map(DemoJSON.int)
            object["context_id_type"] = row.contextIDType.map(DemoJSON.string)
            object["tax"] = row.tax.map { .double(Double($0) / 100) }
            object["tax_receiver_id"] = row.taxReceiverID.map(DemoJSON.int)
            journal.append(.object(object))
            balance -= row.cents
        }
        guard balance >= 0 else { throw DemoExportError.invalidWallet("the opening balance is negative") }
        entries.append(DemoArchive.Entry(operationID: Self.walletJournalOperation, method: "GET", path: base + "/journal",
                                         headers: DemoArchive.Headers(xPages: 1), body: .array(journal)))

        let batch: [DemoJSON] = transactions.sorted { $0.id > $1.id }.map { sale in
            .object([
                "transaction_id": .int(sale.id), "date": .string(DemoRebaser.timestamp(Date(timeIntervalSince1970: TimeInterval(sale.seconds)))),
                "location_id": .int(sale.trade.locationID), "type_id": .int(sale.trade.typeID),
                "unit_price": .double(sale.trade.unitPrice), "quantity": .int(sale.trade.quantity),
                "client_id": .int(sale.trade.clientID), "is_buy": .bool(sale.trade.isBuy), "is_personal": .bool(true),
                "journal_ref_id": .int(journalIDs[sale.id] ?? 0),
            ])
        }
        entries.append(DemoArchive.Entry(operationID: Self.walletTransactionsOperation, method: "GET",
                                         path: base + "/transactions", body: .array(batch)))
        if let oldest = transactions.map(\.id).min() {
            entries.append(DemoArchive.Entry(operationID: Self.walletTransactionsOperation, method: "GET",
                                             path: base + "/transactions", query: "from_id=\(oldest - 1)", body: .array([])))
        }
        return entries
    }

    static func walletDescription(_ entry: DemoConfig.JournalEntry) -> String {
        switch entry.refType {
        case "brokers_fee": "Brokerage fee"
        case "industry_job_tax": "Industry job tax"
        case "manufacturing": "Manufacturing job installation fee"
        case "copying": "Copying job installation fee"
        case "researching_material_productivity": "Material efficiency research fee"
        case "player_donation": entry.amount >= 0 ? "Donation received" : "Donation sent"
        case "insurance": "Insurance payout"
        case "skill_purchase": "Skill purchase"
        case "contract_price": "Contract price"
        default: entry.refType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
