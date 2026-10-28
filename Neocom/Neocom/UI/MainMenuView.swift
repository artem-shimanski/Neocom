import BusinessKit
import KillmailKit
import LiteRow
import LiteRowUI
import MailKit
import SDEKit
import SwiftUI
import TrainingKit

/// The main screen: the pilot card on top, the sections as tiles below.
///
/// One `NavigationSplitView` on every device, the home screen its sidebar and the selected section
/// its detail column. Compact widths collapse it to a stack; regular widths show the columns side
/// by side. A width change keeps the detail stack and every screen on it.
///
/// The tiles are not a `List(selection:)`: a tap sets `selection` and asks for the detail column
/// through `preferredCompactColumn`. The binding is written, never read back, because the collapsed
/// split view also writes `.sidebar` when a screen is popped inside the detail stack. A tap on the
/// selected tile resets the detail stack to the section's root.
///
/// `isHomeOnTop` records whether the home screen was on top at the last collapse, so a return to a
/// narrow width lands on the same screen.
struct MainMenuView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AccountStore.self) private var accounts

    @State private var selection: MainMenuSection?
    /// The column on top while collapsed, set by `open` and by a collapse; never read back.
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    /// The detail stack's path, held here so it survives the split view collapsing and expanding.
    /// Type-erased, because sections push their own route types.
    @State private var detailPath = NavigationPath()
    /// Whether the home screen was on top while collapsed: set by its appearance (reported only
    /// while compact), cleared by `open`, set by `select(nil)`.
    @State private var isHomeOnTop = true
    @State private var isShowingAccounts = false

    /// The sidebar's width while expanded: the narrowest it may go, and the width it takes. The Mac
    /// window's minimum is sized from the latter.
    static let sidebarMinimumWidth: CGFloat = 320
    static let sidebarIdealWidth: CGFloat = 360

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            HomeView(selection: selection, open: open, isShowingAccounts: $isShowingAccounts,
                     reportOnTop: { isHomeOnTop = $0 })
                .navigationSplitViewColumnWidth(min: Self.sidebarMinimumWidth, ideal: Self.sidebarIdealWidth)
        } detail: {
            NavigationStack(path: $detailPath) {
                if let selection {
                    SectionDetailView(section: selection)
                        // Sections link to each other and push onto this stack.
                        .navigationDestination(for: MainMenuSection.self) { section in
                            SectionDetailView(section: section)
                        }
                        // A new section starts from its own root. The root is keyed, not the
                        // stack: a stack replaced while collapsed reports its root disappeared
                        // right after it appears, and the root's tasks stay cancelled.
                        .id(selection)
                } else {
                    // Seen only while expanded: collapsed, nothing selected means the home screen.
                    ContentUnavailableView(
                        "Neocom",
                        systemImage: "sparkles",
                        description: Text("Select a section to get started.")
                    )
                    .hudScreen()
                }
            }
        }
        .sheet(isPresented: $isShowingAccounts) {
            AccountsView()
        }
        // A collapse shows what was on top when it was last collapsed.
        .onChange(of: horizontalSizeClass) {
            preferredCompactColumn = (isHomeOnTop || selection == nil) ? .sidebar : .detail
        }
        // Signed out, the detail column must not keep showing a section that needs an account.
        .onChange(of: accounts.currentAccountID) {
            if accounts.currentAccount == nil, selection?.requiresAccount == true {
                select(nil)
            } else if selection?.group == .corporation, accounts.currentCorporation == nil {
                select(nil)
            }
        }
    }

    /// Shows `section` in the detail column. The same section again opens from its root; another
    /// one starts a fresh stack.
    private func open(_ section: MainMenuSection) {
        if section != selection {
            select(section)
        } else {
            detailPath = NavigationPath()
        }
        isHomeOnTop = false
        preferredCompactColumn = .detail
    }

    /// Changes the section and resets the detail path in one update, so the old path does not land
    /// on the new root.
    private func select(_ section: MainMenuSection?) {
        detailPath = NavigationPath()
        selection = section
        if section == nil {
            isHomeOnTop = true
            preferredCompactColumn = .sidebar
        }
    }
}

/// The home screen's content: the split view's sidebar.
private struct HomeView: View {
    /// The section in the detail column, ringed on its tile while expanded; collapsed, the
    /// home screen is on top and nothing is ringed.
    let selection: MainMenuSection?
    /// Opens a section in the detail column.
    let open: (MainMenuSection) -> Void
    @Binding var isShowingAccounts: Bool
    /// Told `true` when the home screen appears and `false` when it disappears, only while
    /// compact: expanded, the sidebar is always visible and says nothing about what is on top.
    let reportOnTop: (Bool) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AccountStore.self) private var accounts
    @Environment(ServerStatusSheet.self) private var serverStatus

    /// The current character's assets, taken in `.task`: creating the sheet reads its disk cache,
    /// which belongs after the first frame.
    @State private var assets: AssetsSheet?

    /// The current character's Business sheets, for the tiles' counts.
    @State private var orders: OrdersSheet?
    @State private var industry: IndustrySheet?
    @State private var contracts: ContractsSheet?
    /// The current character's corporation: its roles decide the Corporation tiles.
    @State private var corporation: CorporationSheet?
    @State private var corporationOrders: CorporationOrdersSheet?
    @State private var corporationIndustry: CorporationIndustrySheet?
    @State private var corporationContracts: CorporationContractsSheet?
    /// The current character's mail, for the tile's unread count.
    @State private var mail: MailSheet?
    /// The current character's killmails, for the tile's counts.
    @State private var killmails: KillmailsSheet?

    var body: some View {
        HUDList {
            Section {
                pilotCard.hudBareRow()
            } header: {
                // Tranquility's status; public, so shown signed out too.
                if let state = serverStatus.state(now: .now) {
                    serverStatusLine(state).hudListHeader()
                }
            }

            if !SSOConfiguration.isConfigured {
                Section {
                    SetupHintView().hudBareRow()
                }
            }

            if isSignedOut {
                Section {
                    HUDEmptyPanel(title: Text("Sign in to unlock the rest of Neocom"),
                                  message: Text("Skills and training, assets, mail, planets, market orders, industry and contracts open up as soon as a pilot is on board."),
                                  placeholderSystemImage: "lock.open") {
                        if DemoPilot.isAvailable {
                            Button("Explore with a demo pilot") {
                                Task { await accounts.enterDemo() }
                            }
                            .hudProminentButton()
                        }
                    }
                    .hudBareRow()
                }
            }

            ForEach(visibleGroups) { group in
                Section {
                    if group == .corporation, corporationState == .needsSignIn {
                        HUDGrantAccessRow(message: Text("Sign in again to see your corporation's data"))
                            .hudBareRow()
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: HUDMetrics.headerSpacing),
                                            GridItem(.flexible(), spacing: HUDMetrics.headerSpacing)],
                                  spacing: HUDMetrics.headerSpacing) {
                            ForEach(sections(of: group)) { section in
                                tile(for: section)
                            }
                        }
                        // A lazy grid in a list row leaves tiles inserted later blank.
                        .id(sections(of: group))
                        .hudBareRow()
                    }
                } header: {
                    HUDSectionHeader(Text(group.title)) {
                        if isSignedOut && group == .tools {
                            Text("No sign-in needed")
                        }
                    }
                    .hudListHeader()
                }
            }

            Section {
                supportRow
            }
        }
        .navigationTitle("Neocom")
        // Read here, not in `MainMenuView`: this view's environment is the one in effect when the
        // callback fires, so the sidebar appearing during expansion is not taken for the home
        // screen coming on top.
        .onAppear {
            if horizontalSizeClass == .compact { reportOnTop(true) }
        }
        .onDisappear {
            if horizontalSizeClass == .compact { reportOnTop(false) }
        }
        // The menu bar's Settings command (⌘,) opens the section.
        .focusedSceneValue(\.openMainMenuSection, MainMenuSectionOpener(open: open))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(MainMenuSection.settings.title, systemImage: MainMenuSection.settings.systemImage) {
                    open(.settings)
                }
            }
            ToolbarItem {
                Button("Characters", systemImage: "person.2") {
                    isShowingAccounts = true
                }
            }
        }
        // The status line keeps itself fresh while the home screen is on screen; a failed request
        // is retried on the same beat.
        .task {
            await serverStatus.keepFresh()
        }
        // The card shows the wallet and standing, which live in the profile; fetched through the
        // sheet, which coalesces calls from both screens.
        .task(id: accounts.currentAccountID) {
            await accounts.currentSheet?.ensureProfileFresh()
        }
        // Started here so the many-page asset list is usually in by the time the section opens; the
        // section's own call joins this one. Keyed on the sign-in generation too: re-authorizing
        // the selected character replaces its sheet without changing `currentAccountID`.
        .task(id: AssetsTaskKey(characterID: accounts.currentAccountID, signIn: accounts.signInGeneration)) {
            assets = accounts.currentAssets
            await assets?.ensureFresh()
        }
        // The Business tiles count open orders, running jobs and active contracts. Each sheet skips
        // the fetch when the account lacks the scope; the section's own call joins one in flight.
        .task(id: AssetsTaskKey(characterID: accounts.currentAccountID, signIn: accounts.signInGeneration)) {
            let orders = accounts.currentOrders
            let industry = accounts.currentIndustry
            let contracts = accounts.currentContracts
            self.orders = orders
            self.industry = industry
            self.contracts = contracts
            async let ordersDone: Void = orders?.ensureOpenFresh() ?? ()
            async let industryDone: Void = industry?.ensureFresh() ?? ()
            async let contractsDone: Void = contracts?.ensureFresh() ?? ()
            _ = await (ordersDone, industryDone, contractsDone)
        }
        // The Corporation tiles: the roles decide which show, and only those fetch their counts.
        // Corporation assets are never fetched here: the list is far larger than a count is worth.
        .task(id: CorporationTaskKey(characterID: accounts.currentAccountID, signIn: accounts.signInGeneration,
                                     corporationID: accounts.currentAccount.flatMap(accounts.corporationID(of:)))) {
            await loadCorporation()
        }
        // The Mail tile counts unread mail; the sheet skips the labels route without the scope.
        .task(id: AssetsTaskKey(characterID: accounts.currentAccountID, signIn: accounts.signInGeneration)) {
            let mail = accounts.currentMail
            self.mail = mail
            await mail?.ensureLabelsFresh()
        }
        // The Killmails tile counts kills and losses; the sheet skips the routes without the scope.
        .task(id: AssetsTaskKey(characterID: accounts.currentAccountID, signIn: accounts.signInGeneration)) {
            let killmails = accounts.currentKillmails
            self.killmails = killmails
            await killmails?.ensureFresh()
        }
    }

    /// Leads to the Character Sheet; without a character, to the sign-in sheet instead.
    @ViewBuilder private var pilotCard: some View {
        let card = PilotCardView(account: accounts.currentAccount, sheet: accounts.currentSheet)
        if accounts.currentAccount == nil {
            Button { isShowingAccounts = true } label: { card }
                .buttonStyle(.hudTile)
        } else {
            link(to: .characterSheet) { card }
        }
    }

    private var isSignedOut: Bool { accounts.currentAccount == nil }

    /// `● TRANQUILITY · 24,318 ONLINE`, and the same line in `warn` or `danger` when the server
    /// is in VIP mode, in its daily downtime or down.
    private func serverStatusLine(_ state: ServerState) -> HUDStatusLine {
        switch state {
        case let .online(players):
            HUDStatusLine(color: .hudOk, title: Text("Tranquility"),
                          detail: Text("· \(players) online"))
        case .vip:
            HUDStatusLine(color: .hudWarn, title: Text("Tranquility"), titleColor: .hudWarn,
                          detail: Text("· VIP · developers only"))
        case let .downtime(backAbout):
            HUDStatusLine(color: .hudWarn, title: Text("Downtime"), titleColor: .hudWarn,
                          detail: Text("· back about \(EVETime.time(backAbout)) EVE"))
        case .offline:
            HUDStatusLine(color: .hudDanger, title: Text("Tranquility offline"), titleColor: .hudDanger)
        }
    }

    /// The groups to show. Signed out, a group with any account-only section is left out and one
    /// placeholder stands in for all of them.
    private var visibleGroups: [MainMenuSection.Group] {
        MainMenuSection.Group.allCases.filter { group in
            if isSignedOut, group.sections.contains(where: \.requiresAccount) { return false }
            return group != .corporation || corporationState != .hidden
        }
    }

    private enum CorporationState {
        /// Not in a player corporation, its profile is not in yet, or no role opens a section.
        case hidden
        /// The account was signed in before the corporation scopes were asked for.
        case needsSignIn
        case tiles
    }

    /// The sheet of the current character's current corporation, once taken in `.task`.
    private var currentCorporation: CorporationSheet? {
        guard let account = accounts.currentAccount, let corporation,
              corporation.characterID == account.id,
              corporation.corporationID == accounts.corporationID(of: account) else { return nil }
        return corporation
    }

    /// `sheet` if it belongs to the current character's current corporation; a sheet kept from
    /// the previous character stays out until `.task` replaces it.
    private func current<Sheet: CorporationBound>(_ sheet: Sheet?) -> Sheet? {
        guard let sheet, let corporation = currentCorporation,
              sheet.boundCorporationID == corporation.corporationID,
              sheet.characterID == corporation.characterID else { return nil }
        return sheet
    }

    private var corporationState: CorporationState {
        guard let account = accounts.currentAccount, let corporation = currentCorporation else { return .hidden }
        if !SSOConfiguration.Scope.corporation.allSatisfy(account.hasScope) { return .needsSignIn }
        return corporation.access.isEmpty ? .hidden : .tiles
    }

    /// The tiles of `group`; the corporation's are those its roles allow.
    private func sections(of group: MainMenuSection.Group) -> [MainMenuSection] {
        guard group == .corporation else { return group.sections }
        guard let access = currentCorporation?.access else { return [] }
        return group.sections.filter {
            switch $0 {
            case .corporationAssets: access.assets
            case .corporationOrders: access.orders
            case .corporationIndustry: access.industry
            case .corporationContracts: access.contracts
            default: false
            }
        }
    }

    private func loadCorporation() async {
        guard let account = accounts.currentAccount, let corporation = accounts.currentCorporation else {
            corporationOrders = nil
            corporationIndustry = nil
            corporationContracts = nil
            corporation = nil
            return
        }
        self.corporation = corporation
        guard SSOConfiguration.Scope.corporation.allSatisfy(account.hasScope) else { return }
        await corporation.ensureFresh()
        let access = corporation.access
        let orders = access.orders ? accounts.currentCorporationOrders : nil
        let industry = access.industry ? accounts.currentCorporationIndustry : nil
        let contracts = access.contracts ? accounts.currentCorporationContracts : nil
        corporationOrders = orders
        corporationIndustry = industry
        corporationContracts = contracts
        async let ordersDone: Void = orders?.ensureOpenFresh() ?? ()
        async let industryDone: Void = industry?.ensureFresh() ?? ()
        async let contractsDone: Void = contracts?.ensureFresh() ?? ()
        _ = await (ordersDone, industryDone, contractsDone)
    }

    /// A tile with the section's counters and selection ring.
    @ViewBuilder private func tile(for section: MainMenuSection) -> some View {
        link(to: section) {
            switch section {
            case .trainingQueue:
                TrainingTile(sheet: accounts.currentSheet, isSelected: isSelected(section))
            case .assets:
                HUDNavTile(systemImage: section.systemImage,
                           title: Text(section.title),
                           subtitle: assetsSubtitle)
                    .overlay { selectionRing(section) }
            case .skills:
                SkillsTile(injected: accounts.currentSheet?.snapshot?.skills.count)
                    .overlay { selectionRing(section) }
            case .corporationAssets:
                HUDNavTile(systemImage: section.systemImage,
                           title: Text(section.title),
                           subtitle: corporationAssetsSubtitle)
                    .overlay { selectionRing(section) }
            case .marketOrders:
                ordersTile(personalOrders, section: section)
                    .overlay { selectionRing(section) }
            case .corporationOrders:
                ordersTile(current(corporationOrders), section: section)
                    .overlay { selectionRing(section) }
            case .industry:
                industryTile(personalIndustry, section: section)
                    .overlay { selectionRing(section) }
            case .corporationIndustry:
                industryTile(current(corporationIndustry), section: section)
                    .overlay { selectionRing(section) }
            case .contracts:
                contractsTile(personalContracts, section: section)
                    .overlay { selectionRing(section) }
            case .corporationContracts:
                contractsTile(current(corporationContracts), section: section)
                    .overlay { selectionRing(section) }
            case .mail:
                mailTile
                    .overlay { selectionRing(section) }
            case .killmails:
                killmailsTile
                    .overlay { selectionRing(section) }
            case .fittingTool:
                // Signed out, fits are computed with an all-skills-V pilot.
                HUDNavTile(systemImage: section.systemImage,
                           title: Text(section.title),
                           subtitle: isSignedOut ? Text("All skills V") : nil)
                    .overlay { selectionRing(section) }
            default:
                HUDNavTile(systemImage: section.systemImage, title: Text(section.title))
                    .overlay { selectionRing(section) }
            }
        }
    }

    /// The tip jar, a full-width row under the tile groups rather than a tile.
    private var supportRow: some View {
        Button {
            open(.support)
        } label: {
            HUDLinkRowLabel(systemImage: MainMenuSection.support.systemImage,
                            title: Text(MainMenuSection.support.title))
                .overlay {
                    if isSelected(.support) {
                        RoundedRectangle(cornerRadius: HUDMetrics.panelRadius, style: .continuous)
                            .strokeBorder(Color.hudAccent, lineWidth: 1)
                    }
                }
        }
        .hudRowButton()
    }

    @ViewBuilder
    private func link<Label: View>(to section: MainMenuSection, @ViewBuilder label: () -> Label) -> some View {
        // Buttons, not `NavigationLink`s: a `List` row activates every link or default-styled
        // control it holds on a tap, and a group of tiles is one row.
        Button {
            open(section)
        } label: { label() }
            .buttonStyle(.hudTile)
    }

    private struct CorporationTaskKey: Hashable {
        var characterID: Int64?
        var signIn: Int
        var corporationID: Int64?
    }

    /// What the assets task runs again for: another character, or the same one signed in anew.
    private struct AssetsTaskKey: Hashable {
        var characterID: Int64?
        var signIn: Int
    }

    /// `21 locations`, once the list has been fetched for this character.
    private var assetsSubtitle: Text? {
        guard let assets, assets.characterID == accounts.currentAccountID,
              let count = assets.value?.locations.count else { return nil }
        return Text("\(count) locations")
    }

    /// From the cached list only: the home screen does not fetch the corporation's assets.
    private var corporationAssetsSubtitle: Text? {
        guard let account = accounts.currentAccount,
              let sheet = accounts.existingCorporationAssets(for: account) else { return nil }
        if sheet.access == .forbidden { return Text("No access") }
        guard let count = sheet.value?.locations.count else { return nil }
        return Text("\(count) locations")
    }

    private var personalOrders: (any OrdersSource)? {
        orders.flatMap { $0.characterID == accounts.currentAccountID ? $0 : nil }
    }

    private var personalIndustry: (any IndustrySource)? {
        industry.flatMap { $0.characterID == accounts.currentAccountID ? $0 : nil }
    }

    private var personalContracts: (any ContractsSource)? {
        contracts.flatMap { $0.characterID == accounts.currentAccountID ? $0 : nil }
    }

    /// `7 open`, and `2 EXPIRING` in `warn` while orders have less than a day left. Undercut and
    /// outbid are not shown: they need each order's regional book.
    private func ordersTile(_ sheet: (any OrdersSource)?, section: MainMenuSection) -> some View {
        let summary = sheet?.open.value.map { OrdersSummary($0.orders, now: .now) }
        let expiring = summary?.expiringSoonCount ?? 0
        let subtitle: Text? = if let sheet, sheet.access != .granted {
            Text("No access")
        } else {
            summary.map { Text("\($0.openCount) open") }
        }
        return HUDNavTile(systemImage: section.systemImage,
                          title: Text(section.title),
                          subtitle: subtitle,
                          tone: expiring > 0 ? .warn : .normal) {
            if expiring > 0 {
                HUDStatusChip(text: Text("\(expiring) expiring"), color: .hudWarn)
            }
        }
    }

    /// `4 active · 1 paused`, and `1 READY` in `ok` while jobs wait to be delivered.
    private func industryTile(_ sheet: (any IndustrySource)?, section: MainMenuSection) -> some View {
        let summary = sheet?.value.map { IndustrySummary($0.jobs, now: .now) }
        let subtitle: Text? = if let sheet, sheet.access != .granted {
            Text("No access")
        } else if let summary {
            summary.pausedCount > 0
                ? Text("\(summary.activeCount) active · \(summary.pausedCount) paused")
                : Text("\(summary.activeCount) active")
        } else {
            nil
        }
        let ready = summary?.readyCount ?? 0
        return HUDNavTile(systemImage: section.systemImage,
                          title: Text(section.title),
                          subtitle: subtitle) {
            if ready > 0 {
                HUDStatusChip(text: Text("\(ready) ready"), color: .hudOk)
            }
        }
    }

    /// `5 active · 1 to you`; a corporation's, `5 active · 1 to corp`.
    private func contractsTile(_ sheet: (any ContractsSource)?, section: MainMenuSection) -> some View {
        let summary = sheet.flatMap { sheet in
            sheet.value.map { value in
                sheet.corporationID.map { ContractsSummary(value.contracts, corporationID: $0) }
                    ?? ContractsSummary(value.contracts, characterID: sheet.characterID)
            }
        }
        let subtitle: Text? = if let sheet, sheet.access != .granted {
            Text("No access")
        } else if let summary {
            if summary.toYouCount == 0 {
                Text("\(summary.activeCount) active")
            } else if sheet?.corporationID != nil {
                Text("\(summary.activeCount) active · \(summary.toYouCount) to corp")
            } else {
                Text("\(summary.activeCount) active · \(summary.toYouCount) to you")
            }
        } else {
            nil
        }
        return HUDNavTile(systemImage: section.systemImage,
                          title: Text(section.title),
                          subtitle: subtitle)
    }

    /// `5 UNREAD` in `accent`, and `Inbox 3 · [Corp] 2` — the built-in mailboxes with unread
    /// mail; `No unread mail` when there is none.
    private var mailTile: some View {
        let sheet = mail.flatMap { $0.characterID == accounts.currentAccountID ? $0 : nil }
        let summary = sheet?.unreadSummary
        let subtitle: Text? = if sheet?.isMissingScope == true {
            Text("No access")
        } else if let summary {
            summary.mailboxesLine.map { Text(verbatim: $0) } ?? Text("No unread mail")
        } else {
            nil
        }
        let unread = summary?.totalUnread ?? 0
        return HUDNavTile(systemImage: MainMenuSection.mail.systemImage,
                          title: Text(MainMenuSection.mail.title),
                          subtitle: subtitle) {
            if unread > 0 {
                HUDStatusChip(text: Text("\(unread) unread"), color: .hudAccent)
            }
        }
    }

    /// `4 kills · 2 losses` over the killmails loaded so far.
    private var killmailsTile: some View {
        let sheet = killmails.flatMap { $0.characterID == accounts.currentAccountID ? $0 : nil }
        let subtitle: Text? = if sheet?.isMissingScope == true {
            Text("No access")
        } else if let counts = sheet?.counts {
            counts.kills + counts.losses == 0
                ? Text("No killmails")
                : Text("\(counts.kills) kills · \(counts.losses) losses")
        } else {
            nil
        }
        return HUDNavTile(systemImage: MainMenuSection.killmails.systemImage,
                          title: Text(MainMenuSection.killmails.title),
                          subtitle: subtitle)
    }

    private func isSelected(_ section: MainMenuSection) -> Bool {
        horizontalSizeClass != .compact && selection == section
    }

    @ViewBuilder private func selectionRing(_ section: MainMenuSection) -> some View {
        if isSelected(section) {
            RoundedRectangle(cornerRadius: HUDMetrics.tileRadius, style: .continuous)
                .strokeBorder(Color.hudAccent, lineWidth: 1)
        }
    }
}

/// The Training Queue tile: what the game is training and whether it is moving.
///
/// A paused or empty queue turns the tile `warn`.
private struct TrainingTile: View {
    let sheet: CharacterSheet?
    let isSelected: Bool

    @Environment(SDEStore.self) private var sde

    var body: some View {
        let entry = currentEntry
        Group {
            // The skill is named only once another screen has opened the database; the home screen
            // does not load the SDE to spell one name.
            if let entry, case let .ready(database) = sde.state {
                TrainingTileNamed(entry: entry, tone: tone(entry), status: status(entry))
                    .liteDatabase(database.database)
                    // The tile stays on screen while the database language is switched: a new
                    // identity reads the name again.
                    .id(sde.language)
            } else {
                TrainingTileBody(skillName: nil, tone: tone(entry), status: status(entry))
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: HUDMetrics.tileRadius, style: .continuous)
                    .strokeBorder(Color.hudAccent, lineWidth: 1)
            }
        }
    }

    /// The entry the game is working on: the first one that has not finished yet.
    private var currentEntry: CharacterSnapshot.QueueEntry? {
        guard let queue = sheet?.snapshot?.queue else { return nil }
        return queue
            .sorted { $0.position < $1.position }
            .first { ($0.finishDate ?? .distantFuture) > .now }
    }

    private func tone(_ entry: CharacterSnapshot.QueueEntry?) -> HUDTone {
        guard sheet?.snapshot != nil else { return .normal }
        return entry == nil || entry?.finishDate == nil ? .warn : .normal
    }

    private func status(_ entry: CharacterSnapshot.QueueEntry?) -> HUDStatusChip? {
        guard sheet?.snapshot != nil else { return nil }
        guard let entry else { return HUDStatusChip(text: Text("Empty"), color: .hudWarn) }
        guard let finishDate = entry.finishDate else {
            return HUDStatusChip(text: Text("Paused"), color: .hudWarn)
        }
        return HUDStatusChip(text: Text(TrainingTime.string(max(0, finishDate.timeIntervalSinceNow))),
                             color: .hudAccent)
    }
}

/// The tile once the skill in training can be named.
private struct TrainingTileNamed: View {
    let entry: CharacterSnapshot.QueueEntry
    let tone: HUDTone
    let status: HUDStatusChip?

    @LiteQuery private var names: [TypeNameRow]

    init(entry: CharacterSnapshot.QueueEntry, tone: HUDTone, status: HUDStatusChip?) {
        self.entry = entry
        self.tone = tone
        self.status = status
        _names = LiteQuery(SDEBrowser.typeNames(of: [entry.skillID]))
    }

    var body: some View {
        TrainingTileBody(skillName: names.first.map { "\($0.name) \(SkillLevel.roman(entry.finishedLevel))" },
                         tone: tone,
                         status: status)
    }
}

private struct TrainingTileBody: View {
    let skillName: String?
    let tone: HUDTone
    let status: HUDStatusChip?

    var body: some View {
        HUDNavTile(systemImage: MainMenuSection.trainingQueue.systemImage,
                   title: Text(MainMenuSection.trainingQueue.title),
                   subtitle: skillName.map { Text(verbatim: $0) },
                   tone: tone) {
            status
        }
    }
}

/// The Skills tile: `256 of 510`, the injected skills out of every published one.
///
/// The total comes from the SDE and, like the Training tile's skill name, appears only once the
/// database has been opened.
private struct SkillsTile: View {
    /// Skills the character has injected, `nil` before the sheet has loaded.
    let injected: Int?

    @Environment(SDEStore.self) private var sde

    var body: some View {
        if let injected, case let .ready(database) = sde.state {
            SkillsTileCounted(injected: injected)
                .liteDatabase(database.database)
        } else {
            SkillsTileBody(subtitle: injected.map { Text("\($0) skills") })
        }
    }
}

/// The tile once the SDE can count the published skills.
private struct SkillsTileCounted: View {
    let injected: Int

    @LiteQuery private var skills: [SkillListRow]

    init(injected: Int) {
        self.injected = injected
        _skills = LiteQuery(SkillBrowser.skills())
    }

    var body: some View {
        SkillsTileBody(subtitle: skills.isEmpty
            ? Text("\(injected) skills")
            : Text("\(injected) of \(skills.count)"))
    }
}

private struct SkillsTileBody: View {
    let subtitle: Text?

    var body: some View {
        HUDNavTile(systemImage: MainMenuSection.skills.systemImage,
                   title: Text(MainMenuSection.skills.title),
                   subtitle: subtitle)
    }
}

/// Shown until a Client ID is filled in, so a fresh checkout explains itself.
private struct SetupHintView: View {
    var body: some View {
        HUDPanel(tone: .warn) {
            HUDPanelHeader(title: Text("Setup")) {
                HUDStatusChip(text: Text("Not configured"), color: .hudWarn, mark: .symbol("exclamationmark.triangle.fill"))
            }
            Text("EVE SSO is not configured")
                .font(.hudTileTitle)
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.top, 14)
            Text("Register an application at developers.eveonline.com and put its Client ID into SSOConfiguration.clientID.")
                .font(.hudCaption)
                .foregroundStyle(Color.hudWarnNoteInk)
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.top, 6)
                .padding(.bottom, 14)
        }
    }
}

#Preview {
    MainMenuView()
        .environment(AccountStore())
        .environment(SDEStore())
        .environment(ServerStatusSheet())
}
