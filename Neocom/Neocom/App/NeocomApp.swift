import SwiftData
import SwiftUI

@main
struct NeocomApp: App {
    /// The app's only container, built here so that `AccountStore` receives the main context.
    ///
    /// Syncs through `.automatic`: CloudKit when the entitlements declare a container, local
    /// storage otherwise.
    private let modelContainer: ModelContainer
    @State private var accounts: AccountStore
    @State private var fittings: FittingStore
    /// Opened on first use and kept open; the files are large and read-only.
    @State private var sde: SDEStore
    /// The market, public data, and the region it is read in.
    @State private var market = MarketSheet()
    /// zKillboard search; public data, one search at a time.
    @State private var zkillboard = ZKillboardSheet()
    /// Tranquility's status; public.
    @State private var serverStatus = ServerStatusSheet()
    /// Created at launch so that it observes StoreKit's transaction updates from the start.
    @State private var tipJar = TipJar()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before UIKit reads its saved state, which happens right after this initializer.
        LegacySceneSessions.discardIfNeeded()
        // There is no degraded mode without storage; failing at launch is intended.
        let configuration = ModelConfiguration(cloudKitDatabase: .automatic)
        let container = try! ModelContainer(for: TrainingPlanEntry.self, Fitting.self,
                                            configurations: configuration)
        modelContainer = container
        let accounts = AccountStore(modelContext: container.mainContext)
        let sde = SDEStore()
        SDEStore.removeDownloadedLanguages()
        _accounts = State(initialValue: accounts)
        _sde = State(initialValue: sde)
        let fittings = FittingStore(context: container.mainContext)
        _fittings = State(initialValue: fittings)
        // Imports the old app's fits; a no-op after the first successful run.
        Task { await LegacyFitsImport.runIfNeeded(into: fittings) }
        // Rebuilds the notification schedule from the disk cache without fetching, then follows
        // the route owners' reports.
        NotificationPlanner.shared.attach(accounts: accounts, sde: sde)
        // Writes the widgets' snapshot to the App Group.
        WidgetSnapshotWriter.shared.attach(accounts: accounts, sde: sde)
        #if DEBUG
        DemoRecordingPass.startIfRequested(accounts: accounts)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            // Above the menu so that exactly one provider keeps the character snapshot fresh.
            TrainingContextProvider {
                MainMenuView()
            }
            .environment(accounts)
            .environment(fittings)
            .environment(sde)
            .environment(market)
            .environment(zkillboard)
            .environment(serverStatus)
            .environment(tipJar)
            .environment(LocalNotifications.shared)
            .appliesAppTheme()
            #if targetEnvironment(macCatalyst)
            // Sidebar width plus the fit editor's minimum width; below it the editor clips.
            .frame(minWidth: MainMenuView.sidebarIdealWidth + 1 + FittingEditorView.macMinimumWidth,
                   minHeight: 560)
            #endif
        }
        .modelContainer(modelContainer)
        .commands { NeocomCommands() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // The notification authorization may have changed in Settings.
                Task { await NotificationPlanner.shared.refreshAuthorization() }
            case .background:
                NotificationBackgroundCheck.schedule()
                WidgetSnapshotWriter.shared.setNeedsUpdate()
            default:
                break
            }
        }
        // Checks orders, contracts and mail and refreshes scheduled data while the app is closed.
        .backgroundTask(.appRefresh(NotificationBackgroundCheck.taskID)) {
            await NotificationBackgroundCheck.run()
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1200, height: 750)
        .windowResizability(.contentMinSize)
        #endif
    }
}
