import SDEKit
import SwiftUI

/// Settings: notifications, market, data kept on this iPhone, and the app itself (About).
///
/// Each section that changes on its own schedule is a view of its own, so this file only lays them
/// out. Opens the static data for the region's name.
struct SettingsView: View {
    var body: some View {
        SDESectionView { _ in
            SettingsList()
        }
        .hudScreen()
        .navigationTitle(MainMenuSection.settings.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsList: View {
    @Environment(AccountStore.self) private var accounts
    @Environment(MarketSheet.self) private var market
    @Environment(ZKillboardSheet.self) private var zkillboard
    @Environment(ServerStatusSheet.self) private var serverStatus
    @Environment(\.openURL) private var openURL

    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.system

    @State private var isShowingRegions = false
    /// `nil` until the first count, and while a clear is in progress.
    @State private var cache: CachedData.Usage?
    @State private var isConfirmingClear = false

    var body: some View {
        HUDList {
            appearanceSection
            SettingsNotificationsSection()
            marketSection
            dataSection
            aboutSection
        }
        .sheet(isPresented: $isShowingRegions) {
            MarketRegionSheet()
        }
        .confirmationDialog(Text("Clear Cached Data"), isPresented: $isConfirmingClear,
                            titleVisibility: .hidden) {
            Button(role: .destructive) {
                clear()
            } label: {
                Text("Clear \(cacheSize)")
            }
        } message: {
            Text("Neocom will fetch everything from EVE again as you open each screen.")
        }
        .task { cache = await CachedData.usage() }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        HUDListSection("Appearance") {
            HUDIconRow(systemImage: "circle.lefthalf.filled", title: Text("Theme"),
                       subtitle: Text("Auto follows the system")) {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: Market

    private var marketSection: some View {
        let preference = market.regions
        return HUDListSection("Market") {
            Button {
                isShowingRegions = true
            } label: {
                MarketRegionName(regionID: preference.regionID, hubSystemID: nil) { region, _ in
                    HUDLinkRowLabel(systemImage: "map", title: Text("Price Region"),
                                    subtitle: Text("Every item's price comes from it"),
                                    value: region.map { Text(verbatim: $0) })
                }
            }
            .hudRowButton()
            NavigationLink {
                TradeHubsView()
            } label: {
                HUDLinkRowLabel(systemImage: "scope", title: Text("Trade Hubs"),
                                subtitle: Text("Offered first in the region picker"),
                                value: Text(verbatim: "\(MarketRegionPreference.tradeHubs.count) + \(preference.userHubSystemIDs.count)"))
            }
            .hudRowButton()
        }
    }

    // MARK: Data

    private var dataSection: some View {
        HUDListSection("Data") {
            SettingsLanguageRow()
            HUDIconRow(systemImage: "cylinder.split.1x2", title: Text("Cached Data"), subtitle: cacheSubtitle) {
                Button("Clear", role: .destructive) {
                    isConfirmingClear = true
                }
                .buttonStyle(.glass)
                .foregroundStyle(cache?.isEmpty == false ? Color.hudDanger : Color.hudInkFaint)
                .disabled(cache?.isEmpty != false)
            }
        } footer: {
            HUDFootnote("Clearing removes only what came from EVE; it is fetched again as you open each screen. Your fits, the training plan and signed-in pilots stay.")
        }
    }

    #if targetEnvironment(macCatalyst)
    private static let privacySubtitle = Text("Nothing leaves this Mac but EVE requests")
    #else
    private static let privacySubtitle = Text("Nothing leaves this iPhone but EVE requests")
    #endif

    private var cacheSize: String {
        (cache?.bytes ?? 0).formatted(.byteCount(style: .file))
    }

    private var cacheSubtitle: Text? {
        guard let cache else { return Text(verbatim: " ") }
        return cache.isEmpty ? Text("EMPTY · FETCHED AGAIN AS NEEDED")
            : cacheLocation
    }

    #if targetEnvironment(macCatalyst)
    private var cacheLocation: Text { Text("\(cacheSize) on this Mac") }
    #else
    private var cacheLocation: Text { Text("\(cacheSize) on this iPhone") }
    #endif

    private func clear() {
        cache = nil
        CachedData.clear(accounts: accounts, market: self.market, zkillboard: zkillboard,
                         serverStatus: serverStatus)
        Task { cache = await CachedData.usage() }
    }

    // MARK: About

    private var aboutSection: some View {
        HUDListSection {
            NavigationLink(value: MainMenuSection.support) {
                HUDLinkRowLabel(systemImage: MainMenuSection.support.systemImage,
                                title: Text(MainMenuSection.support.title))
            }
            .hudRowButton()
            external(SettingsLinks.review, systemImage: "star", title: Text("Rate on the App Store"),
                     subtitle: Text(verbatim: "apps.apple.com"))
            external(SettingsLinks.sourceCode, systemImage: "chevron.left.forwardslash.chevron.right",
                     title: Text("Source Code"), subtitle: Text(verbatim: "github.com"))
            external(SettingsLinks.privacyPolicy, systemImage: "checkmark.shield",
                     title: Text("Privacy Policy"),
                     subtitle: Self.privacySubtitle)
            NavigationLink {
                LegalView()
            } label: {
                HUDLinkRowLabel(systemImage: "doc.text", title: Text("Legal & Acknowledgements"))
            }
            .hudRowButton()
        } header: {
            HUDSectionHeader(Text("About")) {
                Text("Version \(SettingsLinks.version)")
            }
        } footer: {
            HUDFootnote("EVE Online and the EVE logo are the registered trademarks of Fenris Creations (formerly CCP Games). Neocom is not affiliated with or endorsed by Fenris Creations.")
        }
    }

    private func external(_ url: URL, systemImage: String, title: Text, subtitle: Text) -> some View {
        Button {
            openURL(url)
        } label: {
            HUDLinkRowLabel(systemImage: systemImage, title: title, subtitle: subtitle, destination: .external)
        }
        .hudRowButton()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AccountStore())
    .environment(SDEStore())
    .environment(MarketSheet())
    .environment(ZKillboardSheet())
    .environment(ServerStatusSheet())
    .environment(LocalNotifications.shared)
}
