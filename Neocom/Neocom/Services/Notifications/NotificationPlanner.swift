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
/// value (`ESISnapshot.didUpdate`, wired by `CharacterSheet`, `IndustrySheet`, `ContractsSheet`
/// and their corporation counterparts), when settings or accounts change, and at launch from the
/// disk cache.
///
/// The corporation parts have one scope per corporation, however many of its members are on the
/// device; they are built from the freshest data among the members whose roles open the section.
@MainActor
final class NotificationPlanner {
    static let shared = NotificationPlanner()

    /// The schedule parts built here, one scope per pilot each, or per corporation.
    enum Part: CaseIterable, Hashable {
        case training
        case industry
        case contracts
        case corporationIndustry
        case corporationContracts

        var kind: NotificationKind {
            switch self {
            case .training: .training
            case .industry: .industry
            case .contracts: .contracts
            case .corporationIndustry: .corporationIndustry
            case .corporationContracts: .corporationContracts
            }
        }

        static let pilotParts: [Part] = [.training, .industry, .contracts]
        static let corporationParts: [Part] = [.corporationIndustry, .corporationContracts]
    }

    /// A part of one pilot, or of one corporation for the corporation parts.
    private struct Key: Hashable {
        var part: Part
        var ownerID: Int64
    }

    private enum Plan {
        /// Withdraw the scope.
        case clear
        /// Leave the scope as it is: the data is not at hand.
        case keep
        case moments([Moment], owner: String)
    }

    private(set) weak var accounts: AccountStore?
    private weak var sde: SDEStore?
    private var dirty: Set<Key> = []
    private var forced: Set<Key> = []
    /// The corporation parts of every corporation are to be listed and rebuilt.
    private var corporationsDirty = false
    private var corporationsForced = false
    /// The corporation of each pilot as last seen here.
    private var corporations: [Int64: Int64] = [:]
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
        dirty.insert(Key(part: part, ownerID: characterID))
        flushSoon()
    }

    /// Marks a corporation's part as changed.
    func reschedule(_ part: Part, corporationID: Int64) {
        guard accounts != nil else { return }
        dirty.insert(Key(part: part, ownerID: corporationID))
        flushSoon()
    }

    /// Marks the corporation parts of every corporation, of the pilots and of the scopes on
    /// record, as changed.
    func rescheduleCorporations(force: Bool = false) {
        guard accounts != nil else { return }
        corporationsDirty = true
        if force { corporationsForced = true }
        flushSoon()
    }

    /// Reports a pilot's corporation from a new profile; a change reschedules the corporation
    /// parts.
    func corporationSeen(_ corporationID: Int64, characterID: Int64) {
        guard corporations[characterID] != corporationID, NotificationSettings.load().corporationAny else { return }
        corporations[characterID] = corporationID
        rescheduleCorporations()
    }

    /// Marks every part of every pilot as changed; `force` rebuilds parts that look unchanged.
    func rescheduleAll(force: Bool = false) {
        guard let accounts else { return }
        for account in accounts.accounts {
            for part in Part.pilotParts {
                let key = Key(part: part, ownerID: account.id)
                dirty.insert(key)
                if force { forced.insert(key) }
            }
        }
        rescheduleCorporations(force: force)
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
            while !dirty.isEmpty || corporationsDirty {
                if corporationsDirty {
                    let force = corporationsForced
                    corporationsDirty = false
                    corporationsForced = false
                    await listCorporations(force: force)
                }
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

    /// Marks the corporation parts of the pilots' corporations and of every corporation with a
    /// scope on record, so a corporation nobody sees any more is cleared.
    private func listCorporations(force: Bool) async {
        guard let accounts else { return }
        var ids: Set<Int64> = []
        for part in Part.corporationParts {
            for scope in await LocalNotifications.shared.scopes(prefix: part.kind.prefix) {
                if let id = part.kind.corporationID(ofScope: scope) { ids.insert(id) }
            }
        }
        if NotificationSettings.load().corporationAny {
            for account in accounts.accounts {
                if let id = await profile(of: account)?.corporationID, CorporationSheet.isPlayerCorporation(id) {
                    corporations[account.id] = id
                    ids.insert(id)
                }
            }
        }
        for id in ids {
            for part in Part.corporationParts {
                let key = Key(part: part, ownerID: id)
                dirty.insert(key)
                if force { forced.insert(key) }
            }
        }
    }

    private func build(_ key: Key, force: Bool) async {
        let kind = key.part.kind
        let scope = kind.isCorporation ? kind.scope(corporationID: key.ownerID) : kind.scope(characterID: key.ownerID)
        let plan = kind.isCorporation
            ? await corporationPlan(key.part, corporationID: key.ownerID)
            : await pilotPlan(key.part, characterID: key.ownerID)
        guard case let .moments(moments, owner) = plan else {
            if case .clear = plan { LocalNotifications.shared.replace(scope: scope, with: []) }
            return
        }
        let now = Date.now

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
            let text = moment.text(owner: owner, names: names)
            return LocalNotificationRequest(id: scope + moment.id, title: text.title, body: text.body,
                                            threadID: scope, fireDate: moment.fireDate)
        }
        LocalNotifications.shared.replace(scope: scope, with: requests)
    }

    private func pilotPlan(_ part: Part, characterID: Int64) async -> Plan {
        guard let accounts, let account = accounts.accounts.first(where: { $0.id == characterID }) else {
            return .clear
        }
        let settings = NotificationSettings.load()
        let now = Date.now
        let owner = account.characterName

        switch part {
        case .training:
            guard settings.trainsAlerts(for: account.id) else { return .clear }
            let snapshot = await held(CharacterSheet.trainingCacheKind, characterID: account.id) {
                accounts.existingSheets(for: account).sheet.map(\.snapshot)
            }
            guard let queue = snapshot?.queue else { return .keep }
            return .moments(TrainingReminders.plan(queue: queue, skillTrained: settings.skillTrained,
                                                   queueEnding: settings.queueEnding,
                                                   leadHours: settings.queueLeadHours, now: now)
                .map { Moment(id: $0.id, fireDate: $0.fireDate, source: .training($0)) }, owner: owner)
        case .industry:
            let hasScope = accounts.existingSheets(for: account).industry?.hasScope
                ?? account.hasScope(SSOConfiguration.Scope.industryJobs)
            guard settings.industry, hasScope else { return .clear }
            let jobs = await held(IndustrySheet.cacheKind, characterID: account.id) {
                accounts.existingSheets(for: account).industry.map(\.value)
            }
            guard let value = jobs else { return .keep }
            return .moments(IndustryReminders.plan(value.jobs, now: now)
                .map { Moment(id: "job.\($0.id)", fireDate: $0.endDate, source: .industry($0, value)) }, owner: owner)
        case .contracts:
            let hasScope = accounts.existingSheets(for: account).contracts?.hasScope
                ?? account.hasScope(SSOConfiguration.Scope.contracts)
            guard settings.contracts, hasScope else { return .clear }
            let contracts = await held(ContractsSheet.cacheKind, characterID: account.id) {
                accounts.existingSheets(for: account).contracts.map(\.value)
            }
            guard let value = contracts?.contracts else { return .keep }
            return .moments(ContractReminders.plan(value, characterID: account.id, now: now)
                .map { Moment(id: $0.id, fireDate: $0.fireDate, source: .contract($0)) }, owner: owner)
        case .corporationIndustry, .corporationContracts:
            return .keep
        }
    }

    /// The members on the device who may see a corporation section, by character id; `nil` when
    /// some members' roles are not known yet and none is known to see it.
    private func viewers(of corporationID: Int64, scope: String, members: [Account],
                         access: (CorporationAccess) -> Bool) async -> [Account]? {
        guard let accounts else { return [] }
        var unknown = false
        var viewers: [Account] = []
        for account in members where account.hasScope(scope) && account.hasScope(SSOConfiguration.Scope.corporationRoles) {
            let roles = await held(CorporationSheet.rolesCacheKind(corporationID), characterID: account.id) {
                accounts.existingCorporationSheets(for: account, corporationID: corporationID).corporation.map(\.roles.value)
            }
            guard let roles else {
                unknown = true
                continue
            }
            if access(CorporationSheet.access(roles: roles, hasScope: account.hasScope)) { viewers.append(account) }
        }
        return viewers.isEmpty && unknown ? nil : viewers
    }

    private func corporationPlan(_ part: Part, corporationID: Int64) async -> Plan {
        guard let accounts else { return .clear }
        let settings = NotificationSettings.load()
        let now = Date.now
        guard part == .corporationIndustry ? settings.corporationIndustry : settings.corporationContracts else {
            return .clear
        }
        var members: [Account] = []
        var owner: String?
        var unknown = false
        for account in accounts.accounts.sorted(by: { $0.id < $1.id }) {
            guard let profile = await profile(of: account) else {
                unknown = true
                continue
            }
            guard profile.corporationID == corporationID else { continue }
            members.append(account)
            owner = owner ?? Self.corporationLabel(profile)
        }
        guard let owner else { return unknown ? .keep : .clear }

        switch part {
        case .corporationIndustry:
            guard let viewers = await viewers(of: corporationID, scope: SSOConfiguration.Scope.corporationIndustryJobs,
                                              members: members, access: \.industry)
            else { return .keep }
            if viewers.isEmpty { return .clear }
            var freshest: ESICache.Entry<ESIIndustryJobs>?
            for viewer in viewers {
                let entry = await heldEntry(CorporationIndustrySheet.cacheKind(corporationID), characterID: viewer.id) {
                    accounts.existingCorporationSheets(for: viewer, corporationID: corporationID).industry
                        .map { sheet in sheet.value.map { .init(value: $0, fetchedAt: sheet.fetchedAt ?? .distantPast) } }
                }
                if let entry, freshest == nil || entry.fetchedAt > freshest?.fetchedAt ?? .distantPast { freshest = entry }
            }
            guard let value = freshest?.value else { return .keep }
            // A character's own job list leaves out the jobs it installed for the corporation.
            return .moments(IndustryReminders.plan(value.jobs, now: now)
                .map { Moment(id: "job.\($0.id)", fireDate: $0.endDate, source: .industry($0, value)) }, owner: owner)
        case .corporationContracts:
            let viewers = members.filter { $0.hasScope(SSOConfiguration.Scope.corporationContracts) }
            if viewers.isEmpty { return .clear }
            var freshest: ESICache.Entry<ESIContracts>?
            for viewer in viewers {
                let entry = await heldEntry(CorporationContractsSheet.cacheKind(corporationID), characterID: viewer.id) {
                    accounts.existingCorporationSheets(for: viewer, corporationID: corporationID).contracts
                        .map { sheet in sheet.value.map { .init(value: $0, fetchedAt: sheet.fetchedAt ?? .distantPast) } }
                }
                if let entry, freshest == nil || entry.fetchedAt > freshest?.fetchedAt ?? .distantPast { freshest = entry }
            }
            guard let value = freshest?.value.contracts else { return .keep }
            let parties = Self.contractParties(accounts.accounts)
            return .moments(ContractReminders.plan(value.filter { !parties.isParty(to: $0) },
                                                   corporationID: corporationID, now: now)
                .map { Moment(id: $0.id, fireDate: $0.fireDate, source: .contract($0)) }, owner: owner)
        case .training, .industry, .contracts:
            return .keep
        }
    }

    // MARK: - Data at hand

    /// The owner's value if it exists; otherwise its cache file, read off the main actor to
    /// avoid creating every pilot's sheets at launch. An owner created meanwhile wins.
    private func held<Value: Codable & Sendable>(_ kind: String, characterID: Int64,
                                                 _ value: () -> Value??) async -> Value? {
        await heldEntry(kind, characterID: characterID) {
            value().map { $0.map { ESICache.Entry(value: $0, fetchedAt: .distantPast) } }
        }?.value
    }

    private func heldEntry<Value: Codable & Sendable>(_ kind: String, characterID: Int64,
                                                      _ value: () -> ESICache.Entry<Value>??) async -> ESICache.Entry<Value>? {
        if let value = value() { return value }
        let cached = await Task.detached {
            ESICache().load(Value.self, kind: kind, characterID: characterID)
        }.value
        return value() ?? cached
    }

    private func profile(of account: Account) async -> CharacterProfile? {
        guard let accounts else { return nil }
        return await held(CharacterSheet.profileCacheKind, characterID: account.id) {
            accounts.existingSheets(for: account).sheet.map(\.profile)
        }
    }

    /// How a corporation is named in its notifications: its name and ticker, as EVE shows them.
    static func corporationLabel(_ profile: CharacterProfile?) -> String {
        switch (profile?.corporationName, profile?.corporationTicker) {
        case let (name?, ticker?): "\(name) [\(ticker)]"
        case let (name?, nil): name
        case let (nil, ticker?): "[\(ticker)]"
        case (nil, nil): String(localized: "Corporation")
        }
    }

    /// The pilots on the device whose own contract notifications cover the contracts they are
    /// a party to.
    static func contractParties(_ pilots: [Account]) -> ContractParties {
        ContractParties(ids: Set(pilots.filter { $0.hasScope(SSOConfiguration.Scope.contracts) }.map(\.id)))
    }

    struct ContractParties {
        var ids: Set<Int64>

        func isParty(to contract: Contract) -> Bool {
            ids.contains { !contract.roles(of: $0).isEmpty }
        }
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

    /// `pilot` is the pilot's name, or the corporation's label for a corporation part.
    func text(owner pilot: String, names: [Int64: String]) -> (title: String, body: String) {
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
