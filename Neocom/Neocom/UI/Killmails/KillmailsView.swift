import KillmailKit
import LiteRowUI
import SDEKit
import SwiftUI

/// The Killmails section: the pilot's kills and losses of the last 90 days, from the
/// `KillmailsSheet` — the totals strip, the All / Kills / Losses switch, a row per killmail by
/// day, and "Load Older" for the pages not loaded yet. A row opens the killmail's report.
struct KillmailsView: View {
    var body: some View {
        // The database names ships and systems, and the report's items.
        SDESectionView { database in
            KillmailsBody(database: database)
        }
        .hudScreen()
        .navigationTitle("Killmails")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct KillmailsBody: View {
    let database: SDEDatabase

    @Environment(AccountStore.self) private var accounts

    var body: some View {
        if let sheet = accounts.currentKillmails {
            KillmailsScreen(sheet: sheet, database: database)
                // Another character is another sheet, not this one refilled.
                .id(ObjectIdentifier(sheet))
        }
    }
}

/// Where a row of the list leads.
struct KillmailRoute: Hashable {
    var ref: KillmailRef
}

private struct KillmailsScreen: View {
    let sheet: KillmailsSheet
    let database: SDEDatabase

    @Environment(MarketSheet.self) private var market

    var body: some View {
        Group {
            if sheet.isMissingScope {
                HUDList {
                    Section {
                        HUDGrantAccessPanel(title: Text("No Killmail Access"),
                                            message: Text("Your kills and losses need one more permission. Sign in to EVE again and allow Neocom to read your killmails."))
                            .hudBareRow()
                    }
                }
            } else if let data = sheet.recent.value {
                // The screen's one clock: only the freshness line reads it.
                TimelineView(.everyMinute) { context in
                    KillmailsList(sheet: sheet, data: data, now: context.date)
                }
            } else if case let .failed(error) = sheet.recent.state {
                HUDList {
                    Section {
                        HUDEmptyPanel(title: Text("Killmails Unavailable"), message: Text(error.localizedDescription)) {
                            Button("Retry") {
                                Task { await sheet.refresh() }
                            }
                            .hudProminentButton()
                        }
                        .hudBareRow()
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await sheet.ensureFresh() }
        // The values are estimates from CCP's average prices.
        .task { await market.ensurePricesFresh() }
        .refreshableCommand { await sheet.refresh() }
        .navigationDestination(for: KillmailRoute.self) { route in
            KillmailReportView(sheet: sheet, ref: route.ref)
                .liteDatabase(database.database)
        }
    }
}

// MARK: - List

private struct KillmailsList: View {
    let sheet: KillmailsSheet
    let data: ESIKillmailList
    let now: Date

    @Environment(MarketSheet.self) private var market
    @State private var filter: KillmailFilter = .all
    @State private var loadError: (any Error)?

    var body: some View {
        let pilotID = sheet.characterID
        let killmails = data.loaded
        let price: (Int64) -> Double? = { market.ccpAverage(of: $0) }
        let stats = KillmailListStats(killmails, pilotID: pilotID, price: price)
        let days = KillmailDay.grouped(filter.apply(killmails, pilotID: pilotID))
        let naming = KillmailNaming(names: data.names, sheet: sheet)
        KillmailStaticsReader(systemIDs: killmails.map(\.solarSystemID),
                              typeIDs: killmails.map(\.victim.shipTypeID)) { statics in
            HUDList {
                summary(stats)

                Section {
                    Picker("Killmails", selection: $filter) {
                        ForEach(KillmailFilter.allCases) { filter in
                            Text(verbatim: "\(Self.title(of: filter)) · \(stats.count(for: filter))").tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .hudBareRow()
                }

                if days.isEmpty {
                    Section {
                        HUDEmptyPanel(title: Text(Self.emptyTitle(of: filter)),
                                      message: Text("Ships you help destroy and ships you lose in the last 90 days show here."))
                            .hudBareRow()
                    }
                }

                ForEach(days) { day in
                    HUDListSection(day.killmails, row: { killmail in
                        NavigationLink(value: KillmailRoute(ref: killmail.ref)) {
                            KillmailRow(killmail: killmail, side: sheet.side(of: killmail),
                                        isVictimPilot: killmail.victim.characterID == pilotID,
                                        victim: naming.victim(of: killmail),
                                        shipName: statics.typeName(killmail.victim.shipTypeID),
                                        place: statics.placeLine(killmail.solarSystemID,
                                                                 details: [KillmailText.involved(killmail)]),
                                        value: killmail.value(price: price).total)
                        }
                        .hudRowButton(KillmailRow<EmptyView>.rowStyle)
                        .killmailContextMenu(killID: killmail.ref.id)
                    }, header: {
                        HUDSectionHeader(Text(verbatim: EVETime.date(day.day))) {
                            Text(verbatim: "\(day.killmails.count)")
                        }
                    })
                }

                if sheet.hasOlder {
                    Section {
                        loadOlderRow
                    }
                }

                Section {
                    HUDFootnote("EVE keeps your kills and losses for 90 days and refreshes the list every 5 minutes. ISK values are estimates from average market prices; EVE does not report a value for a killmail.")
                        .hudBareRow()
                }
            }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } }),
            presenting: loadError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private func summary(_ stats: KillmailListStats) -> some View {
        Section {
            HUDPanel {
                HUDStatStrip(items: [
                    .init(id: 0, label: Text("Kills"), value: Text(verbatim: "\(stats.kills)"), color: .hudAccent),
                    .init(id: 1, label: Text("Losses"), value: Text(verbatim: "\(stats.losses)")),
                    .init(id: 2, label: Text("Destroyed"), value: Text(verbatim: KillmailText.isk(stats.iskDestroyed))),
                    .init(id: 3, label: Text("Lost"), value: Text(verbatim: KillmailText.isk(stats.iskLost))),
                ])
                HUDPanelRule()
                Text("ISK · Estimated from average market prices · 90 days")
                    .font(.hudMicro)
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
            .hudBareRow()
        } footer: {
            HUDFreshnessChip(sheet.recent, now: now)
                .hudListFooter()
        }
    }

    private var loadOlderRow: some View {
        HUDLoadMoreRow(detail: data.list.nextPage.map { Text("Page \($0) of \(data.list.totalPages)") },
                       isLoading: sheet.isLoadingOlder, action: loadOlder)
    }

    private func loadOlder() {
        Task {
            do {
                try await sheet.loadOlder()
            } catch {
                loadError = error
            }
        }
    }

    private static func title(of filter: KillmailFilter) -> String {
        switch filter {
        case .all: String(localized: "All")
        case .kills: String(localized: "Kills")
        case .losses: String(localized: "Losses")
        }
    }

    private static func emptyTitle(of filter: KillmailFilter) -> LocalizedStringKey {
        switch filter {
        case .all: "No Killmails"
        case .kills: "No Kills"
        case .losses: "No Losses"
        }
    }
}
