import BusinessKit
import SDEKit
import SwiftUI

/// The corporation's Wallets section: the seven divisions with their balances and the way to
/// Member Taxes. A division opens the same overview as the pilot's wallet; its journal and
/// transactions are fetched only then.
struct CorporationWalletsView: View {
    var body: some View {
        SDESectionView { database in
            CorporationWalletsBody(database: database)
        }
        .hudScreen()
        .navigationTitle("Wallets")
        .navigationBarTitleDisplayMode(.inline)
        .corporationSubtitle(.corporation)
    }
}

private struct CorporationWalletsBody: View {
    let database: SDEDatabase

    @Environment(AccountStore.self) private var accounts
    @State private var store = WalletModelStore()

    var body: some View {
        if let sheet = accounts.currentCorporationWallet {
            CorporationWalletsScreen(sheet: sheet, corporation: accounts.currentCorporation)
                .id(ObjectIdentifier(sheet))
                .walletDestinations(store: store, database: database)
        } else {
            NoCorporationView()
        }
    }
}

private struct CorporationWalletsScreen: View {
    let sheet: CorporationWalletSheet
    let corporation: CorporationSheet?

    var body: some View {
        Group {
            if let access = deniedAccess {
                HUDList {
                    Section {
                        WalletAccessPanel(access: access, isCorporation: true)
                            .hudBareRow()
                    }
                }
            } else if let value = sheet.balances.value {
                TimelineView(.everyMinute) { context in
                    CorporationWalletsList(sheet: sheet, corporation: corporation, wallets: value, now: context.date)
                }
            } else if let error = sheet.balances.state.error {
                HUDList {
                    Section {
                        HUDEmptyPanel(title: Text("Wallets Unavailable"), message: Text(error.localizedDescription)) {
                            Button("Retry") { Task { await sheet.refresh() } }
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
        .task {
            async let divisions: Void = corporation?.ensureDivisionsFresh() ?? ()
            await sheet.ensureFresh()
            await divisions
        }
        .refreshableCommand {
            async let roles: Void = corporation?.refresh() ?? ()
            await sheet.refresh()
            await roles
        }
    }

    /// A missing scope, a `403`, or roles known to lack both accountant roles.
    private var deniedAccess: BusinessAccess? {
        if sheet.access != .granted { return sheet.access }
        if let corporation, corporation.roles.value != nil, !corporation.access.wallets { return .forbidden }
        return nil
    }
}

private struct CorporationWalletsList: View {
    let sheet: CorporationWalletSheet
    let corporation: CorporationSheet?
    let wallets: ESICorporationWallets
    let now: Date

    var body: some View {
        let nets = Dictionary(uniqueKeysWithValues: CorporationWalletSheet.divisions.compactMap { number in
            net(of: number).map { (number, $0) }
        })
        // The total's change is known only once every division holding ISK has been opened.
        let isNetComplete = CorporationWalletSheet.divisions.allSatisfy {
            nets[$0] != nil || (wallets.balances[$0] ?? 0) == 0
        }
        let net = nets.values.reduce(0, +)
        HUDList {
            Section {
                VStack(alignment: .leading, spacing: HUDMetrics.headerSpacing) {
                    HUDPanel {
                        HUDStatStrip(items: [
                            .init(id: 0, label: Text("Total"), value: Text(verbatim: ISK.compact(wallets.total)),
                                  unit: Text(verbatim: "ISK")),
                            .init(id: 1, label: Text("Net · 30D"),
                                  value: Text(verbatim: isNetComplete && !nets.isEmpty ? WalletText.signed(net) : "—"),
                                  color: isNetComplete && !nets.isEmpty ? WalletText.color(net) : .hudInkMuted),
                        ])
                    }
                    HUDFreshnessChip(sheet.balances, now: now, staleAfter: 300)
                }
                .hudLeadingBlock()
            }

            HUDListSection(content: {
                ForEach(Array(CorporationWalletSheet.divisions), id: \.self) { number in
                    NavigationLink(value: WalletRoute(division: number, page: .overview)) {
                        HUDLinkRowLabel(systemImage: "\(number).square",
                                        title: Text(verbatim: name(number)),
                                        subtitle: nets[number].map { $0 == 0 ? Text("No activity · 30D") : Text(verbatim: "\(WalletText.signed($0)) · 30D") },
                                        value: Text(verbatim: ISK.compact(wallets.balances[number] ?? 0)))
                    }
                    .hudRowButton(nets[number] == nil ? .default : .subtitled)
                }
            }, header: {
                HUDSectionHeader(Text("Divisions · \(CorporationWalletSheet.divisions.count)"))
            })

            HUDListSection {
                NavigationLink(value: WalletRoute(division: 1, page: .memberTaxes)) {
                    HUDLinkRowLabel(systemImage: WalletText.systemImage(.corporateTaxes), title: Text("Member Taxes"),
                                    subtitle: taxesSubtitle)
                }
                .hudRowButton(.subtitled)
            }

            Section {
                HUDFootnote("Division names come from the corporation’s settings; a division without one is shown by number. Each division has its own journal and market transactions, loaded when it is opened.")
                    .hudBareRow()
            }
        }
    }

    private func name(_ number: Int) -> String {
        corporation?.walletName(number) ?? ESICorporationDivisions.walletName(number, in: [:])
    }

    /// The division's change over 30 days, if its journal has been opened.
    private func net(of number: Int) -> Double? {
        guard let entries = sheet.existingDivision(number)?.journal.value?.entries else { return nil }
        let series = WalletBalancePoint.series(from: entries, now: now)
        guard let first = series.first, let last = series.last else { return 0 }
        return last.balance - first.balance
    }

    /// `12.4M from 8 members · 30D` once the Master Wallet's journal is in.
    private var taxesSubtitle: Text {
        guard let entries = sheet.existingDivision(1)?.journal.value?.entries,
              let corporationID = sheet.corporationID else {
            return Text("Bounty and mission tax by member")
        }
        let taxes = WalletMemberTaxes(journal: entries, corporationID: corporationID, now: now, period: .month)
        return Text("\(ISK.compact(taxes.total)) from \(taxes.members.count) members · 30D")
    }
}
