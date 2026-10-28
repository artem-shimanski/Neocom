import DemoExport
import DemoFixtures
import Foundation
import Testing

private let demo = "/characters/\(DemoIDs.characterID)"

/// ESI `ref_type` and `context_id_type` values the config may use; the client fails to decode others.
private let refTypes: Set = [
    "bounty_prizes", "brokers_fee", "copying", "ess_escrow_transfer", "industry_job_tax", "insurance", "manufacturing",
    "market_transaction", "player_donation", "researching_material_productivity", "skill_purchase", "transaction_tax",
    "contract_price",
]
private let contextTypes: Set = ["market_transaction_id", "system_id", "industry_job_id", "contract_id", "character_id"]

private func walletArchive(_ config: DemoConfig) throws -> (journal: [DemoJSON], transactions: [DemoJSON], archive: DemoArchive) {
    var recording = fakeRecording()
    // The real pilot's wallet must not survive the export.
    recording.entries.append(entry("GetCharactersCharacterIdWalletJournal", "/characters/\(realID)/wallet/journal", pages: 1,
                                   body: .array([object(["id": .int(1), "amount": .double(123_456.78), "balance": .double(92_183_471.74),
                                                         "date": .string("2026-10-20T10:00:00Z"), "ref_type": .string("player_donation"),
                                                         "description": .string("secret")])])))
    recording.entries.append(entry("GetCharactersCharacterIdWalletTransactions", "/characters/\(realID)/wallet/transactions",
                                   body: .array([object(["transaction_id": .int(5), "client_id": .int(realAlliance)])])))
    let archive = try DemoExporter(config: config).export(recording)
    func body(_ operationID: String, query: String = "") -> [DemoJSON] {
        archive.entries.first { $0.operationID == operationID && $0.path.hasPrefix(demo) && $0.query == query }?.body?.array ?? []
    }
    return (body("GetCharactersCharacterIdWalletJournal"), body("GetCharactersCharacterIdWalletTransactions"), archive)
}

@Suite struct WalletOverlayTests {
    @Test func balancesChainToTheWallet() throws {
        let config = try loadConfig()
        let (journal, _, archive) = try walletArchive(config)
        #expect(journal.count > 100)

        let newest = try #require(journal.first)
        #expect(newest["balance"]?.double == config.pilot.walletBalance)
        let wallet = archive.entries.first { $0.operationID == "GetCharactersCharacterIdWallet" }?.body?.double
        #expect(wallet == newest["balance"]?.double)

        for (newer, older) in zip(journal, journal.dropFirst()) {
            let balance = try #require(older["balance"]?.double)
            let expected = balance + (try #require(newer["amount"]?.double))
            #expect(abs(expected - (try #require(newer["balance"]?.double))) < 0.005)
            #expect((older["date"]?.string ?? "") <= (newer["date"]?.string ?? ""))
        }
        #expect(journal.allSatisfy { ($0["balance"]?.double ?? -1) >= 0 })
        let oldest = try #require(journal.last)
        #expect(try #require(oldest["balance"]?.double) - (try #require(oldest["amount"]?.double)) >= 0)
    }

    @Test func salesPayTheirTax() throws {
        let config = try loadConfig()
        let (journal, transactions, _) = try walletArchive(config)
        let byContext = Dictionary(grouping: journal.filter { $0["ref_type"]?.string == "transaction_tax" },
                                   by: { $0["context_id"]?.int ?? 0 })
        let sales = transactions.filter { $0["is_buy"]?.bool == false }
        #expect(!sales.isEmpty && sales.count < transactions.count)
        for sale in sales {
            let id = try #require(sale["transaction_id"]?.int)
            let tax = try #require(byContext[id]?.first)
            #expect(byContext[id]?.count == 1)
            let gross = try #require(sale["unit_price"]?.double) * Double(try #require(sale["quantity"]?.int))
            #expect(abs(-(try #require(tax["amount"]?.double)) - gross * config.wallet.salesTax) < 0.01)
            #expect(tax["date"] == sale["date"])
        }
        for buy in transactions where buy["is_buy"]?.bool == true {
            #expect(byContext[try #require(buy["transaction_id"]?.int)] == nil)
        }
    }

    @Test func transactionsJoinTheirJournalEntries() throws {
        let config = try loadConfig()
        let (journal, transactions, _) = try walletArchive(config)
        let byID = Dictionary(uniqueKeysWithValues: journal.compactMap { entry in entry["id"]?.int.map { ($0, entry) } })
        #expect(byID.count == journal.count)
        #expect(transactions.count == config.wallet.trades.count)
        for transaction in transactions {
            let id = try #require(transaction["transaction_id"]?.int)
            let reference = try #require(transaction["journal_ref_id"]?.int)
            let entry = try #require(byID[reference])
            #expect(entry["ref_type"]?.string == "market_transaction")
            #expect(entry["context_id"]?.int == id && entry["context_id_type"]?.string == "market_transaction_id")
            #expect(entry["date"] == transaction["date"])
            let value = try #require(transaction["unit_price"]?.double) * Double(try #require(transaction["quantity"]?.int))
            let amount = try #require(entry["amount"]?.double)
            #expect(abs(abs(amount) - value) < 0.01 && (amount < 0) == (transaction["is_buy"]?.bool == true))
        }
    }

    @Test func idsStayInTheSyntheticRange() throws {
        let config = try loadConfig()
        let (journal, transactions, _) = try walletArchive(config)
        for entry in journal {
            #expect(DemoIDs.contains(try #require(entry["id"]?.int)))
            for key in ["first_party_id", "second_party_id"] {
                guard let party = entry[key]?.int else { continue }
                #expect(DemoIDs.contains(party) || (1_000_000 ..< 2_000_000).contains(party))
            }
        }
        for transaction in transactions {
            #expect(DemoIDs.contains(try #require(transaction["transaction_id"]?.int)))
            #expect(DemoIDs.contains(try #require(transaction["client_id"]?.int)))
        }
    }

    @Test func staysInsideTheWindowWithValidEnums() throws {
        let config = try loadConfig()
        let (journal, transactions, archive) = try walletArchive(config)
        let dates = (journal + transactions).compactMap { $0["date"]?.string.flatMap { try? Date($0, strategy: .iso8601) } }
        #expect(dates.count == journal.count + transactions.count)
        let hours = dates.map { archive.recordedAt.timeIntervalSince($0) / 3600 }
        #expect(hours.min() ?? 0 >= 1 && hours.max() ?? 99_999 <= 28 * 24)
        for entry in journal {
            #expect(refTypes.contains(try #require(entry["ref_type"]?.string)))
            if let type = entry["context_id_type"]?.string { #expect(contextTypes.contains(type)) }
            #expect(entry["description"]?.string?.isEmpty == false)
        }
        for entry in journal where entry["ref_type"]?.string == "bounty_prizes" {
            #expect(entry["tax"]?.double ?? 0 > 0 && entry["tax_receiver_id"]?.int == config.pilot.corporationID)
        }
        let costs = Dictionary(grouping: journal.filter { $0["context_id_type"]?.string == "industry_job_id" },
                               by: { $0["context_id"]?.int ?? 0 })
        for job in config.industryJobs {
            let total = (costs[job.jobID] ?? []).reduce(0) { $0 - ($1["amount"]?.double ?? 0) }
            #expect(abs(total - (job.cost ?? 0)) < 0.01)
        }
    }

    @Test func walksTheTransactionsToAnEmptyBatch() throws {
        let config = try loadConfig()
        let (_, transactions, archive) = try walletArchive(config)
        let ids = transactions.compactMap { $0["transaction_id"]?.int }
        let oldest = try #require(ids.min())
        let follow = archive.entries.first { $0.operationID == "GetCharactersCharacterIdWalletTransactions" && $0.query == "from_id=\(oldest - 1)" }
        #expect(follow?.body == .array([]))
        let journal = archive.entries.first { $0.operationID == "GetCharactersCharacterIdWalletJournal" }
        #expect(journal?.query == "" && journal?.headers.xPages == 1)
    }

    @Test func dropsTheRecordedWallet() throws {
        let config = try loadConfig()
        let (journal, transactions, archive) = try walletArchive(config)
        let wallets = archive.entries.filter { $0.operationID.contains("WalletJournal") || $0.operationID.contains("WalletTransactions") }
        #expect(wallets.count == 3)
        #expect(wallets.allSatisfy { $0.path.hasPrefix(demo) })
        #expect(!journal.contains { $0["description"]?.string == "secret" || $0["amount"]?.double == 123_456.78 })
        #expect(!transactions.contains { $0["transaction_id"]?.int == 5 })
    }

    @Test func rejectsEntriesOutsideTheWindow() throws {
        var config = try loadConfig()
        config.wallet.entries[0].hoursAgo = DemoExporter.walletWindowHours + 1
        #expect(throws: DemoExportError.self) { try DemoExporter(config: config).export(fakeRecording()) }
        config = try loadConfig()
        config.wallet.entries[0].hoursAgo = 0.5
        #expect(throws: DemoExportError.self) { try DemoExporter(config: config).export(fakeRecording()) }
    }

    @Test func rejectsANegativeBalance() throws {
        var config = try loadConfig()
        var donation = config.wallet.entries[0]
        donation.hoursAgo = 300
        donation.amount = 80_000_000
        config.wallet.entries.append(donation)
        #expect(throws: DemoExportError.self) { try DemoExporter(config: config).export(fakeRecording()) }
    }

    @Test func appliesToAnExistingArchive() throws {
        let config = try loadConfig()
        let exporter = DemoExporter(config: config)
        var archive = try exporter.export(fakeRecording())
        let before = archive.entries.filter { !$0.operationID.contains("Wallet") || $0.operationID == "GetCharactersCharacterIdWallet" }
        archive.entries.removeAll { $0.operationID.contains("WalletJournal") || $0.operationID.contains("WalletTransactions") }
        try exporter.applyWallet(to: &archive)
        #expect(archive.entries.filter { !$0.operationID.contains("Wallet") || $0.operationID == "GetCharactersCharacterIdWallet" } == before)
        #expect(archive.entries.filter { $0.operationID.contains("WalletJournal") || $0.operationID.contains("WalletTransactions") }.count == 3)
    }
}
