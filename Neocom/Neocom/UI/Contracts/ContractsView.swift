import AssetsKit
import BusinessKit
import LiteRowUI
import SDEKit
import SwiftUI

/// The Contracts section: what the character has outstanding, in progress and finished, from
/// the `ContractsSheet` — the summary strip, the Active / Finished tabs, and a row per
/// contract that opens its detail.
struct ContractsView: View {
    var scope: DataScope = .character

    var body: some View {
        SDESectionView { database in
            if scope == .corporation {
                CorporationContractsBody(database: database)
            } else {
                ContractsBody(database: database)
            }
        }
        .hudScreen()
        .navigationTitle("Contracts")
        .navigationBarTitleDisplayMode(.inline)
        .corporationSubtitle(scope)
    }
}

private struct ContractsBody: View {
    let database: SDEDatabase

    @Environment(AccountStore.self) private var accounts

    var body: some View {
        if let sheet = accounts.currentContracts {
            ContractsScreen(sheet: sheet, database: database)
                // Another character is another sheet, not this one refilled.
                .id(ObjectIdentifier(sheet))
        }
    }
}

private struct CorporationContractsBody: View {
    let database: SDEDatabase

    @Environment(AccountStore.self) private var accounts

    var body: some View {
        if let sheet = accounts.currentCorporationContracts {
            ContractsScreen(sheet: sheet, database: database, corporation: accounts.currentCorporation)
                .id(ObjectIdentifier(sheet))
        } else {
            NoCorporationView()
        }
    }
}

/// Where a row of the list leads.
struct ContractRoute: Hashable {
    var contractID: Int64
}

private struct ContractsScreen: View {
    let sheet: any ContractsSource
    let database: SDEDatabase
    var corporation: CorporationSheet?

    var body: some View {
        Group {
            if sheet.access != .granted {
                HUDList {
                    Section {
                        accessPanel
                            .hudBareRow()
                    }
                }
            } else if let data = sheet.value {
                TimelineView(.everyMinute) { context in
                    ContractsList(sheet: sheet, data: data, now: context.date)
                }
            } else if case let .failed(error) = sheet.state {
                HUDList {
                    Section {
                        HUDEmptyPanel(title: Text("Contracts Unavailable"), message: Text(error.localizedDescription)) {
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
        .refreshableCommand {
            await corporation?.refresh()
            await sheet.refresh()
        }
        .navigationDestination(for: ContractRoute.self) { route in
            ContractDetailView(sheet: sheet, contractID: route.contractID)
                .liteDatabase(database.database)
        }
    }

    @ViewBuilder private var accessPanel: some View {
        HUDBusinessAccessPanel(access: sheet.access,
                               title: Text(sheet.corporationID == nil ? "No Contract Access" : "No Corporation Contract Access"),
                               message: Text(sheet.corporationID == nil
                                             ? "Your contracts need one more permission. Sign in to EVE again and allow Neocom to read your contracts."
                                             : "Corporation contracts need one more permission. Sign in to EVE again and allow Neocom to read your corporation's contracts."))
    }
}

// MARK: - List

private enum ContractSide: Hashable {
    case active
    case finished
}

private struct ContractsList: View {
    let sheet: any ContractsSource
    let data: ESIContracts
    let now: Date

    @State private var side: ContractSide = .active
    @State private var kindFilter: ContractKind?

    var body: some View {
        let me = sheet.characterID
        let corporationID = sheet.corporationID
        let filtered = data.contracts.filter { kindFilter == nil || $0.kind == kindFilter }
        let active = filtered.filter { $0.status.isActive }
        let finished = filtered.filter { !$0.status.isActive }
        ContractPlacesReader(systemIDs: data.contracts.flatMap { [$0.startLocationID, $0.endLocationID] }
            .compactMap { $0 }.compactMap { data.locations[$0]?.solarSystemID },
                             typeIDs: []) { places in
            let context = ContractContext(characterID: me, names: data.names, locations: data.locations, places: places,
                                          corporationID: corporationID)
            HUDList {
                summary(data.contracts)

                Section {
                    Picker("Contracts", selection: $side) {
                        Text(verbatim: "\(String(localized: "contracts.filter.active", defaultValue: "Active", comment: "Segment: active contracts")) · \(active.count)").tag(ContractSide.active)
                        Text(verbatim: "\(String(localized: "contracts.filter.finished", defaultValue: "Finished", comment: "Segment: finished contracts")) · \(finished.count)").tag(ContractSide.finished)
                    }
                    .pickerStyle(.segmented)
                    .hudBareRow()
                }

                switch side {
                case .active:
                    let isForMe: (Contract) -> Bool = { contract in
                        corporationID.map(contract.isForCorporation) ?? contract.isForMe(me)
                    }
                    let forMe = active.filter(isForMe).sorted { Self.soonestFirst($0, $1) }
                    let issued = active.filter { !isForMe($0) }.sorted { Self.soonestFirst($0, $1) }
                    if active.isEmpty { empty(title: "No Active Contracts") }
                    if corporationID == nil {
                        group(Text("For You · \(forMe.count)"), forMe, context)
                        group(Text("Issued by You · \(issued.count)"), issued, context)
                    } else {
                        group(Text("For Corporation · \(forMe.count)"), forMe, context)
                        group(Text("Issued by Corporation · \(issued.count)"), issued, context)
                    }
                case .finished:
                    if finished.isEmpty { empty(title: "No Finished Contracts") }
                    group(Text("Last 30 Days · \(finished.count)"),
                          finished.sorted { $0.closedDate > $1.closedDate }, context)
                }

                Section {
                    HUDFootnote(side == .active
                        ? "EVE refreshes contracts every 5 minutes. An outstanding contract past its expiry stays listed until you remove it in the EVE client. Accept, complete or delete contracts in game."
                        : "Finished contracts stay for 30 days.")
                        .hudBareRow()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Type", selection: $kindFilter) {
                        Text("All Types").tag(ContractKind?.none)
                        ForEach([ContractKind.itemExchange, .auction, .courier, .loan, .unknown], id: \.self) { kind in
                            Label(ContractText.kindTitle(kind), systemImage: ContractText.symbol(kind)).tag(ContractKind?.some(kind))
                        }
                    }
                } label: {
                    Label("Filter by Type", systemImage: kindFilter == nil
                          ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }

    /// Expired and due-soon contracts first: what needs an answer.
    private static func soonestFirst(_ lhs: Contract, _ rhs: Contract) -> Bool {
        (lhs.activeDue ?? .distantFuture) < (rhs.activeDue ?? .distantFuture)
    }

    private func summary(_ contracts: [Contract]) -> some View {
        let figures = sheet.corporationID.map { ContractsSummary(contracts, corporationID: $0) }
            ?? ContractsSummary(contracts, characterID: sheet.characterID)
        return Section {
            HUDPanel {
                HUDStatStrip(items: [
                    .init(id: 0, label: Text("Outstanding"), value: Text(verbatim: "\(figures.outstandingCount)")),
                    .init(id: 1, label: Text("In Progress"), value: Text(verbatim: "\(figures.inProgressCount)")),
                    .init(id: 2, label: sheet.corporationID == nil ? Text("To You") : Text("To Corporation"), value: Text(verbatim: "\(figures.toYouCount)"), color: .hudAccent),
                ])
            }
            .hudBareRow()
        } footer: {
            HUDFreshnessChip(sheet.snapshot, now: now)
                .hudListFooter()
        }
    }

    private func empty(title: LocalizedStringKey) -> some View {
        Section {
            HUDEmptyPanel(title: Text(title),
                          message: Text(sheet.corporationID == nil
                                        ? "Contracts you issue, accept or are offered show here: item exchanges, auctions and courier runs."
                                        : "Contracts your corporation issues, accepts or is offered show here: item exchanges, auctions and courier runs."))
                .hudBareRow()
        }
    }

    @ViewBuilder
    private func group(_ title: Text, _ contracts: [Contract], _ context: ContractContext) -> some View {
        if !contracts.isEmpty {
            HUDListSection(contracts, row: { contract in
                NavigationLink(value: ContractRoute(contractID: contract.id)) {
                    ContractRow(contract: contract, context: context, now: now)
                }
                .hudRowButton(ContractRow.rowStyle)
                .contextMenu {
                    HUDCopyButton("Copy Title", value: context.title(of: contract))
                }
            }, header: {
                HUDSectionHeader(title)
            })
        }
    }
}

/// One contract of the list: what it is, what it pays, who it is with, how it stands and when.
private struct ContractRow: View {
    static let rowStyle = HUDRowStyle(minHeight: 0, verticalPadding: 12)

    let contract: Contract
    let context: ContractContext
    let now: Date

    var body: some View {
        let stateColor = ContractText.stateColor(of: contract, now: now)
        HStack(alignment: .top, spacing: 12) {
            HUDSymbolPlate(systemImage: ContractText.symbol(contract.kind), size: 36)
                .opacity(contract.status.isActive ? 1 : 0.7)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: context.title(of: contract))
                        .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(contract.status.isActive ? Color.hudInk : Color.hudInkBodyMuted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: figure)
                        .font(.hudFigure)
                        .lineLimit(1)
                        .fixedSize()
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: meta)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: figureLabel)
                        .lineLimit(1)
                        .fixedSize()
                }
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .foregroundStyle(Color.hudInkMuted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HUDStatusChip(text: Text(verbatim: ContractText.state(of: contract, now: now)),
                                  color: stateColor, mark: .dot)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: when)
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .textCase(.uppercase)
                        .foregroundStyle(whenColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .hudRow(Self.rowStyle)
    }

    /// The price, the reward or the starting bid; `—` for a contract that asks nothing.
    private var figure: String {
        guard let value = headline.value, value > 0 else { return "—" }
        return ISK.priceFigure(value)
    }

    private var figureLabel: String {
        guard let value = headline.value, value > 0 else { return "" }
        return "\(headline.label) ISK".uppercased()
    }

    private var headline: (value: Double?, label: String) {
        switch contract.kind {
        case .courier: (contract.reward, String(localized: "Reward"))
        case .auction: (contract.price, String(localized: "Start"))
        default:
            // An exchange where the issuer pays ("I will pay") carries the ISK as `reward`.
            (contract.price ?? 0) <= 0 && (contract.reward ?? 0) > 0
                ? (contract.reward, String(localized: "Pays"))
                : (contract.price, String(localized: "Price"))
        }
    }

    /// `COURIER · PERSONAL · FROM OSKAR TIDEWATER`.
    private var meta: String {
        [ContractText.kindTitle(contract.kind), ContractText.availabilityTitle(contract.availability),
         context.party(of: contract)].joined(separator: " · ").uppercased()
    }

    private var when: String {
        guard contract.status.isActive else { return EVETime.date(contract.closedDate) }
        if contract.isExpired(at: now) {
            return String(localized: "Since \(EVETime.date(contract.dateExpired))")
        }
        if contract.isOverdue(at: now), let deadline = contract.deadline {
            return String(localized: "Overdue since \(EVETime.date(deadline))")
        }
        let left = EVETime.duration(contract.timeLeft(at: now))
        return contract.status == .inProgress && contract.kind == .courier
            ? String(localized: "Deliver in \(left)")
            : String(localized: "Expires in \(left)")
    }

    private var whenColor: Color {
        contract.isExpired(at: now) || contract.isOverdue(at: now) || contract.isDueSoon(at: now) ? .hudWarn : .hudInkMuted
    }
}
