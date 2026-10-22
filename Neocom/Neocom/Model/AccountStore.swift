import DemoFixtures
import ESIKit
import Foundation
import Observation
import SDEKit
import SwiftData
import TrainingKit

/// The authorized characters, the selected one, and their ESI clients and per-character sheets.
@Observable
@MainActor
final class AccountStore {
    /// The signed-in characters. Never contains the demo pilot.
    private(set) var accounts: [Account] = []

    /// The demo pilot while the demo is on. Kept out of `accounts`, so widgets, notifications
    /// and background checks never see it.
    private(set) var demoAccount: Account?

    var currentAccountID: Int64? {
        didSet {
            defaults.set(currentAccountID.map(NSNumber.init), forKey: Self.currentAccountKey)
            // Unconfigured widgets show the selected pilot.
            WidgetSnapshotWriter.shared.setNeedsUpdate()
        }
    }

    var currentAccount: Account? {
        guard let currentAccountID else { return nil }
        if let demoAccount, demoAccount.id == currentAccountID { return demoAccount }
        return accounts.first { $0.id == currentAccountID }
    }

    /// The characters a fit can be flown by: the signed-in ones and the demo pilot.
    var pickerAccounts: [Account] {
        demoAccount.map { accounts + [$0] } ?? accounts
    }

    @ObservationIgnored private let keychain: Keychain
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let authenticator: SSOAuthenticator
    /// The app-wide SwiftData context; `nil` in previews and tests, which then have no plans.
    @ObservationIgnored private let modelContext: ModelContext?

    // Sessions, sheets and plans are created lazily, one per character, and kept for the
    // account's lifetime. A session holds the cached access token. Sheets that depend on a
    // scope are created with the account's current scopes; a new sign-in drops them.
    @ObservationIgnored private var sessions: [Int64: AccountSession] = [:]
    @ObservationIgnored private var sheets: [Int64: CharacterSheet] = [:]
    @ObservationIgnored private var fittingSheets: [Int64: FittingsSheet] = [:]
    @ObservationIgnored private var planetSheets: [Int64: PlanetsSheet] = [:]
    @ObservationIgnored private var assetSheets: [Int64: AssetsSheet] = [:]
    @ObservationIgnored private var orderSheets: [Int64: OrdersSheet] = [:]
    @ObservationIgnored private var industrySheets: [Int64: IndustrySheet] = [:]
    @ObservationIgnored private var contractSheets: [Int64: ContractsSheet] = [:]
    @ObservationIgnored private var mailSheets: [Int64: MailSheet] = [:]
    @ObservationIgnored private var killmailSheets: [Int64: KillmailsSheet] = [:]
    @ObservationIgnored private var plans: [Int64: TrainingPlanStore] = [:]
    /// The demo pilot's training plan lives in memory only, never in the CloudKit container.
    @ObservationIgnored private var demoPlanContainer: ModelContainer?

    /// Incremented by every sign-in and by `dropCachedData()`. Re-authorizing the selected
    /// character replaces its sheets without changing `currentAccountID`; views observe this to
    /// refetch.
    private(set) var signInGeneration = 0

    private static let accountsKey = "accounts"
    private static let currentAccountKey = "currentAccountID"
    private static let demoActiveKey = "demoPilotActive"

    /// Dependencies are optional so the defaults are created on the main actor.
    init(keychain: Keychain? = nil,
         defaults: UserDefaults = .standard,
         authenticator: SSOAuthenticator? = nil,
         modelContext: ModelContext? = nil) {
        self.keychain = keychain ?? Keychain()
        self.defaults = defaults
        self.authenticator = authenticator ?? .shared
        self.modelContext = modelContext
        load()
    }

    // MARK: - Authorization

    /// Presents EVE SSO and adds (or re-authorizes) a character.
    @discardableResult
    func signIn() async throws -> Account {
        let (claims, token) = try await authenticator.signIn()
        let account = Account(claims: claims, token: token)
        exitDemo()
        // A re-authorization brings a new token pair and possibly new scopes.
        dropState(of: account.id)
        upsert(account)
        currentAccountID = account.id
        signInGeneration += 1
        return account
    }

    func remove(_ account: Account) {
        // Removes the character's training plan and ESI cache; other characters are unaffected.
        plan(for: account)?.clear()
        accounts.removeAll { $0.id == account.id }
        dropState(of: account.id)
        ESICache().removeAll(characterID: account.id)
        LocalNotifications.shared.removeAll(characterID: account.id)
        if currentAccountID == account.id {
            currentAccountID = accounts.first?.id
        }
        save()
        WidgetSnapshotWriter.shared.setNeedsUpdate()
    }

    /// Drops the session, sheets and plan of a character.
    private func dropState(of characterID: Int64) {
        sessions[characterID] = nil
        sheets[characterID] = nil
        fittingSheets[characterID] = nil
        planetSheets[characterID] = nil
        // Invalidated so a long fetch does not write its file back after the cache is cleared
        // or over the new sheet's file.
        assetSheets[characterID]?.invalidate()
        assetSheets[characterID] = nil
        dropBusinessSheets(of: characterID)
        dropMailSheet(of: characterID)
        dropKillmailsSheet(of: characterID)
        plans[characterID] = nil
    }

    // MARK: - Demo

    /// Selects the demo pilot, starting from a clean cache; no-op when the app has no demo data.
    func enterDemo() {
        guard let archive = DemoPilot.archive else { return }
        if demoAccount == nil {
            ESICache().removeAll(characterID: archive.pilot.id)
            demoAccount = Account(demo: archive.pilot)
            defaults.set(true, forKey: Self.demoActiveKey)
        }
        currentAccountID = archive.pilot.id
    }

    /// Ends the demo and drops everything it cached; selects the first signed-in character.
    func exitDemo() {
        guard let demoAccount else { return }
        self.demoAccount = nil
        defaults.set(false, forKey: Self.demoActiveKey)
        dropState(of: demoAccount.id)
        demoPlanContainer = nil
        ESICache().removeAll(characterID: demoAccount.id)
        if currentAccountID == demoAccount.id {
            currentAccountID = accounts.first?.id
        }
    }

    /// Invalidates and drops every character's sheets; called by `CachedData.clear`. Sessions
    /// and training plans are kept. Increments `signInGeneration` so screens refetch.
    func dropCachedData() {
        sheets.values.forEach { $0.invalidate() }
        sheets = [:]
        fittingSheets.values.forEach { $0.invalidate() }
        fittingSheets = [:]
        planetSheets.values.forEach { $0.invalidate() }
        planetSheets = [:]
        assetSheets.values.forEach { $0.invalidate() }
        assetSheets = [:]
        for characterID in Set(orderSheets.keys).union(industrySheets.keys).union(contractSheets.keys) {
            dropBusinessSheets(of: characterID)
        }
        for characterID in Array(mailSheets.keys) {
            dropMailSheet(of: characterID)
        }
        for characterID in Array(killmailSheets.keys) {
            dropKillmailsSheet(of: characterID)
        }
        signInGeneration += 1
        WidgetSnapshotWriter.shared.setNeedsUpdate()
    }

    // MARK: - ESI

    /// An ESI client authenticated as `account`; refreshes the token on expiry and on `401`.
    func client(for account: Account) -> Client {
        session(for: account).client
    }

    /// The selected character's client. Public data uses ``ESIService/publicClient``.
    var currentClient: Client? {
        currentAccount.map(client(for:))
    }

    func sheet(for account: Account) -> CharacterSheet {
        if let sheet = sheets[account.id] { return sheet }

        let sheet = CharacterSheet(characterID: account.id, client: client(for: account))
        sheets[account.id] = sheet
        return sheet
    }

    /// The sheets of `account` created so far, without creating any (creating one reads its
    /// disk cache on the main actor).
    func existingSheets(for account: Account) -> (sheet: CharacterSheet?, industry: IndustrySheet?,
                                                  contracts: ContractsSheet?) {
        (sheets[account.id], industrySheets[account.id], contractSheets[account.id])
    }

    var currentSheet: CharacterSheet? {
        currentAccount.map(sheet(for:))
    }

    func fittings(for account: Account) -> FittingsSheet {
        if let sheet = fittingSheets[account.id] { return sheet }

        let sheet = FittingsSheet(characterID: account.id, client: client(for: account))
        fittingSheets[account.id] = sheet
        return sheet
    }

    var currentFittings: FittingsSheet? {
        currentAccount.map(fittings(for:))
    }

    func planets(for account: Account) -> PlanetsSheet {
        if let sheet = planetSheets[account.id] { return sheet }

        let sheet = PlanetsSheet(characterID: account.id, client: client(for: account))
        planetSheets[account.id] = sheet
        return sheet
    }

    var currentPlanets: PlanetsSheet? {
        currentAccount.map(planets(for:))
    }

    func assets(for account: Account) -> AssetsSheet {
        if let sheet = assetSheets[account.id] { return sheet }

        let sheet = AssetsSheet(characterID: account.id, client: client(for: account))
        assetSheets[account.id] = sheet
        return sheet
    }

    var currentAssets: AssetsSheet? {
        currentAccount.map(assets(for:))
    }

    func orders(for account: Account) -> OrdersSheet {
        if let sheet = orderSheets[account.id] { return sheet }

        let sheet = OrdersSheet(characterID: account.id, client: client(for: account),
                                hasScope: account.hasScope(SSOConfiguration.Scope.marketOrders))
        orderSheets[account.id] = sheet
        return sheet
    }

    var currentOrders: OrdersSheet? {
        currentAccount.map(orders(for:))
    }

    func industry(for account: Account) -> IndustrySheet {
        if let sheet = industrySheets[account.id] { return sheet }

        let sheet = IndustrySheet(characterID: account.id, client: client(for: account),
                                  hasScope: account.hasScope(SSOConfiguration.Scope.industryJobs))
        industrySheets[account.id] = sheet
        return sheet
    }

    var currentIndustry: IndustrySheet? {
        currentAccount.map(industry(for:))
    }

    func contracts(for account: Account) -> ContractsSheet {
        if let sheet = contractSheets[account.id] { return sheet }

        let sheet = ContractsSheet(characterID: account.id, client: client(for: account),
                                   hasScope: account.hasScope(SSOConfiguration.Scope.contracts))
        contractSheets[account.id] = sheet
        return sheet
    }

    var currentContracts: ContractsSheet? {
        currentAccount.map(contracts(for:))
    }

    /// Invalidates and drops the Business sheets, so in-flight fetches write no files.
    private func dropBusinessSheets(of characterID: Int64) {
        orderSheets[characterID]?.invalidate()
        orderSheets[characterID] = nil
        industrySheets[characterID]?.invalidate()
        industrySheets[characterID] = nil
        contractSheets[characterID]?.invalidate()
        contractSheets[characterID] = nil
    }

    func mail(for account: Account) -> MailSheet {
        if let sheet = mailSheets[account.id] { return sheet }

        let sheet = MailSheet(characterID: account.id, client: client(for: account), scopes: account.hasScope)
        mailSheets[account.id] = sheet
        return sheet
    }

    var currentMail: MailSheet? {
        currentAccount.map(mail(for:))
    }

    private func dropMailSheet(of characterID: Int64) {
        mailSheets[characterID]?.invalidate()
        mailSheets[characterID] = nil
    }

    func killmails(for account: Account) -> KillmailsSheet {
        if let sheet = killmailSheets[account.id] { return sheet }

        // The demo pilot's killmails are recorded, so their bodies come from its own client.
        let client = client(for: account)
        let sheet = KillmailsSheet(characterID: account.id, client: client,
                                   publicClient: account.isDemo ? client : ESIService.publicClient,
                                   scopes: account.hasScope)
        killmailSheets[account.id] = sheet
        return sheet
    }

    var currentKillmails: KillmailsSheet? {
        currentAccount.map(killmails(for:))
    }

    private func dropKillmailsSheet(of characterID: Int64) {
        killmailSheets[characterID]?.invalidate()
        killmailSheets[characterID] = nil
    }

    // MARK: - Training plans

    /// The training plan of `account`; `nil` without a model context (previews, tests).
    func plan(for account: Account) -> TrainingPlanStore? {
        if let plan = plans[account.id] { return plan }
        if account.isDemo { return demoPlan(for: account) }
        guard let modelContext else { return nil }

        let plan = TrainingPlanStore(context: modelContext, characterID: account.id)
        plans[account.id] = plan
        return plan
    }

    var currentPlan: TrainingPlanStore? {
        currentAccount.flatMap(plan(for:))
    }

    /// The demo pilot's plan in an in-memory container, seeded from the demo data.
    private func demoPlan(for account: Account) -> TrainingPlanStore? {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        guard let container = try? ModelContainer(for: TrainingPlanEntry.self, configurations: configuration)
        else { return nil }
        demoPlanContainer = container
        let plan = TrainingPlanStore(context: container.mainContext, characterID: account.id)
        let items = DemoPilot.archive?.plan ?? []
        plan.add(items.map { SkillCatalog.Requirement(skillID: TypeID(rawValue: UInt32(clamping: $0.skillID)),
                                                      level: $0.level) })
        plans[account.id] = plan
        return plan
    }

    private func session(for account: Account) -> AccountSession {
        if let session = sessions[account.id] { return session }

        let session = if account.isDemo, let archive = DemoPilot.archive {
            AccountSession(demoClient: ESIService.demoClient(archive: archive))
        } else {
            AccountSession(account: account) { [weak self] token in
                await self?.replaceToken(token, of: account.id)
            }
        }
        sessions[account.id] = session
        return session
    }

    /// Persists a rotated token pair; EVE SSO has invalidated the previous refresh token.
    private func replaceToken(_ token: SSOToken, of characterID: Int64) {
        guard let index = accounts.firstIndex(where: { $0.id == characterID }) else { return }
        accounts[index].token = token
        save()
    }

    // MARK: - Persistence

    private func upsert(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        accounts.sort { $0.characterName.localizedStandardCompare($1.characterName) == .orderedAscending }
        save()
        WidgetSnapshotWriter.shared.setNeedsUpdate()
    }

    private func load() {
        if let data = keychain.data(forKey: Self.accountsKey),
           let stored = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = stored
        }
        if defaults.bool(forKey: Self.demoActiveKey) {
            if let archive = DemoPilot.archive {
                // Recorded dates are rebased on every fetch; nothing cached survives a launch.
                ESICache().removeAll(characterID: archive.pilot.id)
                demoAccount = Account(demo: archive.pilot)
            } else {
                defaults.set(false, forKey: Self.demoActiveKey)
            }
        }
        let storedID = (defaults.object(forKey: Self.currentAccountKey) as? NSNumber)?.int64Value
        currentAccountID = pickerAccounts.contains { $0.id == storedID } ? storedID : accounts.first?.id
    }

    private func save() {
        // Refresh tokens are credentials, so the list is stored in the keychain.
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        try? keychain.set(data, forKey: Self.accountsKey)
    }
}
