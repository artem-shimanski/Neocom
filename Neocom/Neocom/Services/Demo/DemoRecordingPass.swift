#if DEBUG
import BusinessKit
import DemoKit
import Foundation
import KillmailKit
import MailKit
import os

/// Developer tool for the demo fixtures. With `-NeocomRecordDemo YES` it refreshes every route
/// of the selected pilot through the route owners, opens a sample of detail routes, and writes
/// what `ESIService.demoRecorder` saw to `Library/Caches/DemoRecording/recording.json`.
@MainActor
enum DemoRecordingPass {
    private static let contractLimit = 20
    private static let mailLimit = 10
    private static let killmailLimit = 10

    private static var isStarted = false
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Neocom", category: "Demo")

    static var outputURL: URL {
        URL.cachesDirectory.appending(path: "DemoRecording/recording.json")
    }

    /// Starts the pass once per launch when the recorder is on.
    static func startIfRequested(accounts: AccountStore) {
        guard let recorder = ESIService.demoRecorder, !isStarted else { return }
        isStarted = true
        Task { await run(accounts: accounts, recorder: recorder) }
    }

    private static func run(accounts: AccountStore, recorder: DemoRecorder) async {
        guard let account = accounts.currentAccount, !account.isDemo else {
            log.error("Demo recording: no signed-in pilot selected")
            return
        }
        log.notice("Demo recording: started for \(account.characterID, privacy: .public)")

        // Failures stay in each snapshot's state; the pass records whatever answered.
        await accounts.sheet(for: account).refresh()
        await accounts.fittings(for: account).refresh()
        await accounts.planets(for: account).refresh()
        await accounts.assets(for: account).refresh()
        await accounts.orders(for: account).refresh()
        await accounts.industry(for: account).refresh()

        let contracts = accounts.contracts(for: account)
        await contracts.refresh()
        for contract in (contracts.value?.contracts ?? []).prefix(contractLimit) {
            await contracts.items(of: contract.id).refresh()
            if contract.type == "auction" {
                await contracts.bids(of: contract.id).refresh()
            }
        }

        let mail = accounts.mail(for: account)
        await mail.refresh()
        await mail.contacts.refresh()
        let all = mail.headers(for: .all)
        await all.refresh()
        for label in mail.labels.value?.labels ?? [] {
            await mail.headers(for: .label(label.id)).refresh()
        }
        for header in (all.value?.list.headers ?? []).prefix(mailLimit) {
            await mail.message(header.id).refresh()
        }

        let killmails = accounts.killmails(for: account)
        await killmails.refresh()
        for ref in (killmails.recent.value?.list.refs ?? []).prefix(killmailLimit) {
            await killmails.killmail(ref).refresh()
        }

        do {
            try recorder.write(to: outputURL, pilotID: account.characterID, ownerHash: account.ownerHash)
            log.notice("Demo recording: \(recorder.entryCount, privacy: .public) entries written to \(outputURL.path(percentEncoded: false), privacy: .public)")
        } catch {
            log.error("Demo recording: write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
