import BackgroundTasks
import BusinessKit
import Foundation
import MailKit
import WidgetKit

/// The state the last background check saw for one pilot (open orders, active contract
/// statuses, newest mail), used to detect changes. Stored in the character's `ESICache`, so
/// clearing the cache makes the next check record a new baseline silently.
///
/// A field is `nil` before its first check and while its kind is disabled, so re-enabling it
/// does not report everything in between.
///
/// Each field is saved separately together with the start time of the check that wrote it
/// (`*Run`), so an interrupted or overlapping check never overwrites a newer baseline.
nonisolated struct NotificationBaseline: Codable, Sendable, Hashable {
    var orders: OrderWatch.Baseline?
    var contracts: ContractWatch.Baseline?
    var mail: MailWatch.Baseline?
    var ordersRun: Date?
    var contractsRun: Date?
    var mailRun: Date?

    enum Field: Sendable {
        case orders, contracts, mail
    }

    /// The start time of the check that last wrote `field`.
    func run(of field: Field) -> Date? {
        switch field {
        case .orders: ordersRun
        case .contracts: contractsRun
        case .mail: mailRun
        }
    }

    mutating func setRun(_ run: Date, of field: Field) {
        switch field {
        case .orders: ordersRun = run
        case .contracts: contractsRun = run
        case .mail: mailRun = run
        }
    }

    static let kind = "notification-baseline"
}

/// The `BGAppRefreshTask` behind server-detected notifications (orders filled or expired,
/// contracts finished, new mail) and the refresh of scheduled ones while the app is closed.
/// iOS decides when it runs.
///
/// Makes no ESI calls of its own: it refreshes each pilot's route owners. Training and industry
/// reschedule through `NotificationPlanner`; orders, contracts and mail are compared with the
/// baseline and changes are posted immediately.
@MainActor
enum NotificationBackgroundCheck {
    /// Matches `BGTaskSchedulerPermittedIdentifiers` in `Info.plist`.
    nonisolated static var taskID: String { (Bundle.main.bundleIdentifier ?? "Neocom") + ".refresh" }

    /// The minimum interval between checks.
    private static let interval: TimeInterval = 30 * 60
    /// The total budget; iOS gives a refresh task about 30 seconds.
    private static let budget: Duration = .seconds(25)
    /// The part of `budget` reserved for writing the widget snapshot.
    private static let flushBudget: Duration = .seconds(4)

    /// Whether a Neocom widget is installed; its data is kept fresh even with every
    /// notification disabled.
    private static func widgetsInstalled() async -> Bool {
        guard let configurations = try? await WidgetCenter.shared.currentConfigurations() else { return false }
        return configurations.contains { WidgetKind.all.contains($0.kind) }
    }

    /// Submits the next check, or cancels it when there are no accounts, or no enabled kind
    /// needs it and no widget is installed.
    static func schedule() {
        guard let accounts = NotificationPlanner.shared.accounts, !accounts.accounts.isEmpty else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
            return
        }
        Task {
            if NotificationSettings.load().needsBackgroundCheck {
                submit()
            } else if await widgetsInstalled() {
                submit()
            } else {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
            }
        }
    }

    private static func submit() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date.now.addingTimeInterval(interval)
        // Rejected in the simulator and with Background App Refresh disabled.
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The task: checks every pilot concurrently within `budget`, returning early when iOS
    /// cancels the task. The next check is submitted first in case this one is cut short.
    static func run() async {
        schedule()
        guard let accounts = NotificationPlanner.shared.accounts else { return }
        let settings = NotificationSettings.load()
        let run = Date.now
        let clock = ContinuousClock()
        let started = clock.now
        // With every notification disabled only the widgets' pilots are refreshed.
        let widgetsOnly = settings.needsBackgroundCheck ? false : await widgetsInstalled()
        await withDeadline(budget - flushBudget - (clock.now - started)) {
            await withTaskGroup(of: Void.self) { group in
                for account in accounts.accounts {
                    group.addTask {
                        await refresh(account, accounts: accounts, settings: settings, run: run,
                                      widgetsOnly: widgetsOnly)
                    }
                }
            }
        }
        // The snapshot writer debounces its writes and the process may be suspended before
        // that, so the remaining budget is spent on an explicit flush.
        guard !Task.isCancelled else { return }
        await withDeadline(budget - (clock.now - started)) {
            await WidgetSnapshotWriter.shared.flush()
        }
    }

    // MARK: - Pilot

    private static func refresh(_ account: Account, accounts: AccountStore, settings: NotificationSettings,
                                run: Date, widgetsOnly: Bool) async {
        if widgetsOnly {
            await accounts.sheet(for: account).ensureFresh()
        } else {
            await check(account, accounts: accounts, settings: settings, run: run)
        }
    }

    private static func check(_ account: Account, accounts: AccountStore, settings: NotificationSettings,
                              run: Date) async {
        let previous = loadBaseline(characterID: account.id)

        // Scheduled kinds: refreshing the owners triggers the planner.
        let sheet = accounts.sheet(for: account)
        let industry = accounts.industry(for: account)
        async let training: Void = settings.trainsAlerts(for: account.id) ? sheet.ensureFresh() : ()
        async let jobs: Void = settings.industry ? industry.ensureFresh() : ()

        // A disabled kind discards its baseline.
        if !settings.orders { _ = storeBaseline(.orders, characterID: account.id, run: run) { $0.orders = nil } }
        if !settings.contracts { _ = storeBaseline(.contracts, characterID: account.id, run: run) { $0.contracts = nil } }
        if !settings.mail { _ = storeBaseline(.mail, characterID: account.id, run: run) { $0.mail = nil } }

        async let orders: Void = settings.orders
            ? checkOrders(account, accounts: accounts, baseline: previous.orders, run: run) : ()
        async let contracts: Void = settings.contracts
            ? checkContracts(account, accounts: accounts, baseline: previous.contracts, run: run) : ()
        async let mail: Void = settings.mail
            ? checkMail(account, accounts: accounts, baseline: previous.mail, run: run) : ()
        _ = await (training, jobs, orders, contracts, mail)
    }

    /// Writes one kind's new baseline by applying `update` to the stored one. Returns `false`
    /// without writing when the task is cancelled or a check started after `run` has already
    /// written this kind. Callers post only after `true`, with no suspension in between, so a
    /// saved baseline and its notifications stay consistent.
    private static func storeBaseline(_ field: NotificationBaseline.Field, characterID: Int64, run: Date,
                                      update: (inout NotificationBaseline) -> Void) -> Bool {
        guard !Task.isCancelled else { return false }
        var baseline = loadBaseline(characterID: characterID)
        if let written = baseline.run(of: field), written > run { return false }
        update(&baseline)
        baseline.setRun(run, of: field)
        ESICache().save(.init(value: baseline, fetchedAt: .now), kind: NotificationBaseline.kind,
                        characterID: characterID)
        return true
    }

    private static func loadBaseline(characterID: Int64) -> NotificationBaseline {
        ESICache().load(NotificationBaseline.self, kind: NotificationBaseline.kind,
                        characterID: characterID)?.value ?? NotificationBaseline()
    }

    /// Leaves the baseline unchanged when the data could not be compared.
    private static func checkOrders(_ account: Account, accounts: AccountStore,
                                    baseline: OrderWatch.Baseline?, run: Date) async {
        let sheet = accounts.orders(for: account)
        guard sheet.hasScope else { return }
        await sheet.refresh()
        guard sheet.open.state.error == nil, sheet.history.state.error == nil,
              let open = sheet.open.value, let history = sheet.history.value else { return }
        let result = OrderWatch.check(open: open.orders, history: history.orders, baseline: baseline)
        let names = result.closed.isEmpty
            ? [:] : await NotificationPlanner.shared.typeNames(result.closed.map(\.typeID))
        guard storeBaseline(.orders, characterID: account.id, run: run, update: { $0.orders = result.baseline })
        else { return }
        for order in result.closed {
            let item = names[order.typeID] ?? String(localized: "An item")
            let side = order.isBuyOrder ? String(localized: "Buy order") : String(localized: "Sell order")
            let title = order.outcome == .filled
                ? String(localized: "\(side) filled")
                : String(localized: "\(side) expired")
            let body = order.outcome == .filled
                ? String(localized: "\(account.characterName): \(item) × \(order.volumeTotal.formatted()) is done.")
                : String(localized: "\(account.characterName): \(item), \(order.volumeRemain.formatted()) of \(order.volumeTotal.formatted()) left.")
            post(.orders, account: account, id: "\(order.id)", title: title, body: body)
        }
    }

    private static func checkContracts(_ account: Account, accounts: AccountStore,
                                       baseline: ContractWatch.Baseline?, run: Date) async {
        let sheet = accounts.contracts(for: account)
        guard sheet.hasScope else { return }
        await sheet.refresh()
        guard sheet.state.error == nil, let value = sheet.value else { return }
        let result = ContractWatch.check(value.contracts, characterID: account.id, baseline: baseline)
        guard storeBaseline(.contracts, characterID: account.id, run: run, update: { $0.contracts = result.baseline })
        else { return }
        for contract in result.finished {
            let label = contract.title ?? ContractText.kindTitle(contract.kind)
            let title: String
            switch contract.status {
            case .rejected: title = String(localized: "Contract rejected")
            case .failed: title = contract.kind == .courier ? String(localized: "Courier failed") : String(localized: "Contract failed")
            case .reversed: title = String(localized: "Contract reversed")
            default: title = String(localized: "Contract finished")
            }
            post(.contracts, account: account, id: "done.\(contract.id)", title: title,
                 body: "\(account.characterName): \(label)")
        }
    }

    private static func checkMail(_ account: Account, accounts: AccountStore,
                                  baseline: MailWatch.Baseline?, run: Date) async {
        let sheet = accounts.mail(for: account)
        guard sheet.hasReadScope else { return }
        let inbox = sheet.headers(in: .inbox)
        await inbox.refresh()
        guard inbox.state.error == nil, let value = inbox.value else { return }
        let result = MailWatch.check(value.list.headers, characterID: account.id, baseline: baseline)
        guard storeBaseline(.mail, characterID: account.id, run: run, update: { $0.mail = result.baseline }),
              let newest = result.new.first else { return }
        if result.new.count == 1 {
            let from = value.names[newest.from]?.name
            post(.mail, account: account, id: "\(newest.id)",
                 title: from.map { String(localized: "Mail from \($0)") } ?? String(localized: "New mail"),
                 body: "\(account.characterName): \(newest.subject)")
        } else {
            let subjects = result.new.prefix(3).map(\.subject).joined(separator: " · ")
            post(.mail, account: account, id: "\(newest.id)",
                 title: String(localized: "\(result.new.count) new mails"),
                 body: "\(account.characterName): \(subjects)")
        }
    }

    private static func post(_ kind: NotificationKind, account: Account, id: String, title: String, body: String) {
        let scope = kind.scope(characterID: account.id)
        LocalNotifications.shared.post(id: scope + id, title: title, body: body, threadID: scope)
    }

    // MARK: - Budget

    /// Runs `work` until it finishes, `limit` passes or the caller is cancelled, whichever
    /// comes first, then cancels it. Unsaved work is redone by the next check.
    private static func withDeadline(_ limit: Duration, _ work: @escaping @MainActor () async -> Void) async {
        let gate = Gate()
        let worker = Task { @MainActor in
            await work()
            gate.open()
        }
        let timer = Task {
            try? await Task.sleep(for: limit)
            gate.open()
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.wait(continuation)
            }
        } onCancel: {
            gate.open()
        }
        worker.cancel()
        timer.cancel()
    }

    /// A continuation resumed once, by whichever of the work, the timer and the cancellation
    /// comes first.
    private nonisolated final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        private var continuation: CheckedContinuation<Void, Never>?

        func wait(_ continuation: CheckedContinuation<Void, Never>) {
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func open() {
            lock.lock()
            isOpen = true
            let continuation = continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume()
        }
    }
}
