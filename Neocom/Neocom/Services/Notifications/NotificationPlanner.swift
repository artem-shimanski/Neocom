import AssetsKit
import BusinessKit
import Foundation
import LiteRow
import SDEKit
import TrainingKit

/// Builds the local notifications for known future moments (skill trained, queue ending,
/// industry job done, contract expiring) and passes them to `LocalNotifications`.
///
/// Makes no ESI calls: each part is rebuilt from its owner's snapshot when it reports a new
/// value (`ESISnapshot.didUpdate`, wired by `CharacterSheet`, `IndustrySheet` and
/// `ContractsSheet`), when settings change, and at launch from the disk cache.
@MainActor
final class NotificationPlanner {
    static let shared = NotificationPlanner()

    /// The schedule parts built here, one scope per pilot each.
    enum Part: CaseIterable, Hashable {
        case training
        case industry
        case contracts

        var kind: NotificationKind {
            switch self {
            case .training: .training
            case .industry: .industry
            case .contracts: .contracts
            }
        }
    }

    private struct Key: Hashable {
        var part: Part
        var characterID: Int64
    }

    private(set) weak var accounts: AccountStore?
    private weak var sde: SDEStore?
    private var dirty: Set<Key> = []
    private var forced: Set<Key> = []
    private var flushing: Task<Void, Never>?

    private init() {}

    /// Called once at launch. Builds every part from the disk cache without fetching.
    func attach(accounts: AccountStore, sde: SDEStore) {
        self.accounts = accounts
        self.sde = sde
        Task {
            await LocalNotifications.shared.refreshStatus()
            rescheduleAll()
        }
    }

    /// Marks a pilot's part as changed.
    func reschedule(_ part: Part, characterID: Int64) {
        guard accounts != nil else { return }
        dirty.insert(Key(part: part, characterID: characterID))
        flushSoon()
    }

    /// Marks every part of every pilot as changed; `force` rebuilds parts that look unchanged.
    func rescheduleAll(force: Bool = false) {
        guard let accounts else { return }
        for account in accounts.accounts {
            for part in Part.allCases {
                let key = Key(part: part, characterID: account.id)
                dirty.insert(key)
                if force { forced.insert(key) }
            }
        }
        flushSoon()
    }

    /// Rechecks authorization when the app enters the foreground.
    func refreshAuthorization() async {
        let previous = LocalNotifications.shared.status
        let current = await LocalNotifications.shared.refreshStatus()
        if previous != nil, previous != current {
            rescheduleAll(force: true)
        }
    }

    /// Applies changed notification settings.
    func settingsChanged() {
        rescheduleAll()
        NotificationBackgroundCheck.schedule()
    }

    // MARK: - Building

    /// Coalesces reports that arrive together (the training routes, every pilot at launch)
    /// into one pass.
    private func flushSoon() {
        guard flushing == nil else { return }
        flushing = Task {
            try? await Task.sleep(for: .milliseconds(300))
            while !dirty.isEmpty {
                let work = dirty
                let force = forced
                dirty = []
                forced = []
                for key in work {
                    await build(key, force: force.contains(key))
                }
            }
            flushing = nil
        }
    }

    private func build(_ key: Key, force: Bool) async {
        guard let accounts else { return }
        let scope = key.part.kind.scope(characterID: key.characterID)
        guard let account = accounts.accounts.first(where: { $0.id == key.characterID }) else {
            LocalNotifications.shared.replace(scope: scope, with: [])
            return
        }
        let settings = NotificationSettings.load()
        let now = Date.now

        // The owner's value if it exists; otherwise its cache file, read off the main actor to
        // avoid creating every pilot's sheets at launch. An owner created meanwhile wins.
        func held<Value: Codable & Sendable>(_ kind: String, _ value: () -> Value??) async -> Value? {
            if let value = value() { return value }
            let characterID = account.id
            let cached = await Task.detached {
                ESICache().load(Value.self, kind: kind, characterID: characterID)?.value
            }.value
            return value() ?? cached
        }

        let moments: [Moment]
        switch key.part {
        case .training:
            guard settings.trainsAlerts(for: account.id) else { return clear(scope) }
            let snapshot = await held(CharacterSheet.trainingCacheKind) {
                accounts.existingSheets(for: account).sheet.map(\.snapshot)
            }
            guard let queue = snapshot?.queue else { return }
            moments = TrainingReminders.plan(queue: queue, skillTrained: settings.skillTrained,
                                             queueEnding: settings.queueEnding,
                                             leadHours: settings.queueLeadHours, now: now)
                .map { Moment(id: $0.id, fireDate: $0.fireDate, source: .training($0)) }
        case .industry:
            let hasScope = accounts.existingSheets(for: account).industry?.hasScope
                ?? account.hasScope(SSOConfiguration.Scope.industryJobs)
            guard settings.industry, hasScope else { return clear(scope) }
            let jobs = await held(IndustrySheet.cacheKind) {
                accounts.existingSheets(for: account).industry.map(\.value)
            }
            guard let value = jobs else { return }
            moments = IndustryReminders.plan(value.jobs, now: now)
                .map { Moment(id: "job.\($0.id)", fireDate: $0.endDate, source: .industry($0, value)) }
        case .contracts:
            let hasScope = accounts.existingSheets(for: account).contracts?.hasScope
                ?? account.hasScope(SSOConfiguration.Scope.contracts)
            guard settings.contracts, hasScope else { return clear(scope) }
            let contracts = await held(ContractsSheet.cacheKind) {
                accounts.existingSheets(for: account).contracts.map(\.value)
            }
            guard let value = contracts?.contracts else { return }
            moments = ContractReminders.plan(value, characterID: account.id, now: now)
                .map { Moment(id: $0.id, fireDate: $0.fireDate, source: .contract($0)) }
        }

        // Skip unchanged moments; training reports every minute while the app is open.
        if !force {
            let known = LocalNotifications.shared.planned(prefix: scope, now: now)
            let current = known.isEmpty ? await LocalNotifications.shared.pending(prefix: scope) : known
            if Set(current.map { Stamp(id: $0.id, date: $0.fireDate) })
                == Set(moments.map { Stamp(id: scope + $0.id, date: $0.fireDate) }) {
                return
            }
        }

        let names = await typeNames(moments.compactMap(\.typeID))
        let requests = moments.map { moment in
            let text = moment.text(pilot: account.characterName, names: names)
            return LocalNotificationRequest(id: scope + moment.id, title: text.title, body: text.body,
                                            threadID: scope, fireDate: moment.fireDate)
        }
        LocalNotifications.shared.replace(scope: scope, with: requests)
    }

    private func clear(_ scope: String) {
        LocalNotifications.shared.replace(scope: scope, with: [])
    }

    private struct Stamp: Hashable {
        var id: String
        var date: Date
    }

    /// Item names for the notification text, loading the SDE if needed. Empty when the SDE
    /// cannot be opened; the text then omits the name.
    func typeNames(_ ids: [Int64]) async -> [Int64: String] {
        guard let sde, !ids.isEmpty else { return [:] }
        await sde.load()
        guard case let .ready(database) = sde.state else { return [:] }
        let query = SDEBrowser.typeNames(of: Array(Set(ids)).map { TypeID(rawValue: UInt32(clamping: $0)) })
        let rows = (try? await database.database.read { reader in try reader.fetchAll(query) }) ?? []
        return Dictionary(rows.map { (Int64($0.id.rawValue), $0.name) }, uniquingKeysWith: { first, _ in first })
    }
}

/// One scheduled moment of a part, before it is formatted.
private struct Moment {
    enum Source {
        case training(TrainingReminder)
        case industry(IndustryJob, ESIIndustryJobs)
        case contract(ContractReminder)
    }

    var id: String
    var fireDate: Date
    var source: Source

    var typeID: Int64? {
        switch source {
        case let .training(reminder):
            switch reminder.kind {
            case let .skillTrained(skillID, _), let .queueEnding(skillID, _, _): Int64(skillID.rawValue)
            }
        case let .industry(job, _): job.productTypeID ?? job.blueprintTypeID
        case .contract: nil
        }
    }

    func text(pilot: String, names: [Int64: String]) -> (title: String, body: String) {
        let name = typeID.flatMap { names[$0] }
        switch source {
        case let .training(reminder):
            switch reminder.kind {
            case let .skillTrained(_, level):
                let skill = name.map { "\($0) \(SkillLevel.roman(level))" }
                return (skill.map { String(localized: "\($0) trained") } ?? String(localized: "Skill trained"),
                        skill.map { String(localized: "\(pilot) has finished training \($0).") }
                            ?? String(localized: "\(pilot) has finished training a skill."))
            case let .queueEnding(_, level, lead):
                let skill = name.map { "\($0) \(SkillLevel.roman(level))" } ?? String(localized: "the last skill")
                let at = EVETime.dateTime(reminder.eventDate)
                if lead == 0 {
                    return (String(localized: "Training queue ended"),
                            String(localized: "\(pilot): \(skill), the last skill in the queue, has finished. Add skills so training never stops."))
                }
                return (String(localized: "Training queue ends in \(lead) hours"),
                        String(localized: "\(pilot): \(skill), the last skill in the queue, finishes at \(at). Add skills so training never stops."))
            }
        case let .industry(job, value):
            let what = [job.activity.title, name].compactMap { $0 }.joined(separator: " · ")
            let place = value.locations[job.facilityID]?.name ?? value.locations[job.stationID]?.name
            return (String(localized: "Job ready to deliver"),
                    place.map { String(localized: "\(pilot): \(what) is ready at \($0).") }
                        ?? String(localized: "\(pilot): \(what) is ready."))
        case let .contract(reminder):
            let label = reminder.contract.title ?? ContractText.kindTitle(reminder.contract.kind)
            let at = EVETime.dateTime(reminder.eventDate)
            let hours = Int(ContractReminders.lead / 3600)
            switch reminder.kind {
            case .expires:
                return (String(localized: "Contract expires in \(hours) hours"),
                        String(localized: "\(pilot): \(label) expires at \(at)."))
            case .courierDue:
                return (String(localized: "Courier due in \(hours) hours"),
                        String(localized: "\(pilot): \(label) is due at \(at)."))
            }
        }
    }
}
