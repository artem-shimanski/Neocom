import AssetsKit
import BusinessKit
import SDEKit
import SwiftUI

/// One contract: the layout of its kind — item exchange, auction or courier; a loan or a kind
/// ESI adds later reads as an exchange. The items and the bids load for this contract only,
/// through the sheet that owns them.
struct ContractDetailView: View {
    let sheet: ContractsSheet
    let contractID: Int64

    var body: some View {
        Group {
            if let data = sheet.value, let contract = data.contracts.first(where: { $0.id == contractID }) {
                ContractDetailBody(sheet: sheet, data: data, contract: contract)
            } else {
                ContentUnavailableView("Contract Unavailable", systemImage: "doc.questionmark",
                                       description: Text("This contract is no longer in the list."))
            }
        }
        .hudScreen()
    }
}

private struct ContractDetailBody: View {
    let sheet: ContractsSheet
    let data: ESIContracts
    let contract: Contract
    let items: ESISnapshot<[ContractItem]>
    let bids: ESISnapshot<ESIContractBids>?

    @Environment(AccountStore.self) private var accounts
    @Environment(MarketSheet.self) private var market

    init(sheet: ContractsSheet, data: ESIContracts, contract: Contract) {
        self.sheet = sheet
        self.data = data
        self.contract = contract
        items = sheet.items(of: contract.id)
        bids = contract.kind == .auction ? sheet.bids(of: contract.id) : nil
    }

    private var characterSheet: CharacterSheet? { accounts.currentSheet }
    private var startSystemID: Int64? { data.locations[contract.startLocationID ?? 0]?.solarSystemID }
    private var endSystemID: Int64? { data.locations[contract.endLocationID ?? 0]?.solarSystemID }

    var body: some View {
        let pilotSystemID = characterSheet?.currentSolarSystemID
        let systemIDs = [startSystemID, endSystemID, pilotSystemID].compactMap { $0 }
        ContractPlacesReader(systemIDs: systemIDs, typeIDs: (items.value ?? []).map(\.typeID)) { places in
            TimelineView(.everyMinute) { timeline in
                let names = data.names.merging(bids?.value?.names ?? [:]) { first, _ in first }
                let detail = ContractDetail(
                    contract: contract,
                    context: ContractContext(characterID: sheet.characterID, names: names,
                                             locations: data.locations, places: places),
                    items: items, bids: bids, now: timeline.date, pilotSystemID: pilotSystemID, market: market)
                HUDList {
                    switch contract.kind {
                    case .auction: ContractAuctionLayout(detail: detail)
                    case .courier: ContractCourierLayout(detail: detail)
                    case .itemExchange, .loan, .unknown: ContractExchangeLayout(detail: detail)
                    }
                }
                .navigationTitle(navigationTitle(detail.context))
                .navigationSubtitle(contract.kind == .courier ? Text("Courier contract") : Text("Contract"))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task(id: pilotSystemID) { await resolveJumps(pilotSystemID) }
        .refreshableCommand { await refresh() }
    }

    private func navigationTitle(_ context: ContractContext) -> String {
        if contract.kind == .courier,
           let from = context.system(of: contract.startLocationID)?.name,
           let to = context.system(of: contract.endLocationID)?.name {
            return "\(from) → \(to)"
        }
        return ContractText.kindTitle(contract.kind)
    }

    private func load() async {
        async let itemsDone: Void = items.ensureFresh()
        async let bidsDone: Void? = bids?.ensureFresh()
        async let location: Void? = characterSheet?.ensureLocationKnown()
        _ = await (itemsDone, bidsDone, location)
    }

    private func refresh() async {
        async let itemsDone: Void = items.refresh()
        async let bidsDone: Void? = bids?.refresh()
        async let listDone: Void = sheet.refresh()
        _ = await (itemsDone, bidsDone, listDone)
    }

    /// Jumps to the contract's places from the pilot, and — for a courier — along its route.
    private func resolveJumps(_ pilot: Int64?) async {
        let places = [startSystemID, endSystemID].compactMap { $0 }
        if let pilot { await market.resolveJumps(from: pilot, to: places) }
        if contract.kind == .courier, let start = startSystemID, let end = endSystemID {
            await market.resolveJumps(from: start, to: [end])
        }
    }
}

// MARK: - Item exchange

/// The exchange layout — also the fallback for a loan or a kind not known yet.
struct ContractExchangeLayout: View {
    let detail: ContractDetail

    var body: some View {
        let c = detail.contract
        let mine = detail.isMine
        let left = detail.timeLeftFigure
        Section {
            HUDPanel(tone: detail.cardTone) {
                detail.headerBar
                ContractTitleBlock(title: detail.context.title(of: c), party: party)
                HUDPanelRule()
                contractStrip([
                    (Text(verbatim: priceLabel), priceFigure, .hudAccent),
                    (Text("Volume"), c.volume.map { ContractText.volume($0) } ?? "—", .hudInk),
                    (Text(c.status.isActive ? "Expires In" : "Closed"),
                     c.status.isActive ? left.text : EVETime.date(c.closedDate), c.status.isActive ? left.color : .hudInk),
                ])
                if let note {
                    detail.note(note, color: detail.isDueSoon ? .hudWarn : .hudInkMuted)
                }
            }
            .hudBareRow()
        }

        ContractItemsSection(detail: detail, title: Text(mine ? "You Give" : "You Get"), included: true, volume: c.volume)
        ContractItemsSection(detail: detail, title: Text(mine ? "You Ask For" : "They Ask For"), included: false)
        ContractLocationSection(detail: detail, title: "Location", locationID: c.startLocationID)
        detail.parties(last: .init(label: "Accepted By", value: detail.acceptor))
        ContractFactsSection(title: "Contract", facts: [
            .init(label: "Price", value: c.price.map { ContractText.isk($0) } ?? "—", color: .hudAccent),
            .init(label: "Reward", value: c.reward.flatMap { $0 > 0 ? ContractText.isk($0) : nil } ?? "—"),
            .init(label: "Volume", value: c.volume.map { ContractText.volume($0) } ?? "—"),
            .init(label: "Issued", value: detail.date(c.dateIssued)),
            .init(label: "Expires", value: detail.date(c.dateExpired), color: detail.isActive && detail.isDueSoon ? .hudWarn : .hudInk),
            .init(label: "Accepted", value: detail.date(c.dateAccepted)),
            .init(label: "Completed", value: detail.date(c.dateCompleted)),
            detail.contractID,
        ])
        Section {
            HUDFootnote(mine
                ? Text("Whoever accepts pays the price, hands over what you ask for and receives everything you give. Delete or change it in the EVE client.")
                : Text("Items stay at the station until you take them."))
                .hudBareRow()
        }
    }

    private var party: String {
        let c = detail.contract
        if detail.isMine {
            var text = String(localized: "Issued by you")
            if c.acceptorID != 0 { text += " · " + String(localized: "accepted by \(detail.name(c.acceptorID))") }
            return text
        }
        let issuer = detail.name(c.issuerID)
        return c.assigneeID == detail.me ? String(localized: "From \(issuer) · to you") : String(localized: "From \(issuer)")
    }

    /// Whether the issuer pays ISK ("I will pay", ESI's `reward`) instead of asking for it.
    private var issuerPays: Bool {
        (detail.contract.price ?? 0) <= 0 && (detail.contract.reward ?? 0) > 0
    }

    private var priceLabel: String {
        if issuerPays {
            guard detail.contract.status == .outstanding else { return String(localized: "Reward").uppercased() }
            return (detail.isMine ? String(localized: "You pay") : String(localized: "You get")).uppercased()
        }
        guard detail.contract.status == .outstanding else { return String(localized: "Price").uppercased() }
        return (detail.isMine ? String(localized: "You get") : String(localized: "You pay")).uppercased()
    }

    private var priceFigure: String {
        let value = issuerPays ? detail.contract.reward : detail.contract.price
        guard let value, value > 0 else { return "—" }
        return ISK.compact(value)
    }

    /// An offer to the pilot: what to do and by when.
    private var note: String? {
        let c = detail.contract
        guard c.status == .outstanding, !detail.isMine, !c.isExpired(at: detail.now) else { return nil }
        let until = EVETime.dateTime(c.dateExpired)
        let price = c.price.map { ContractText.isk($0) } ?? "0 ISK"
        return c.assigneeID == detail.me
            ? String(localized: "Offered only to you. Accept it in the EVE client before \(until); you pay \(price).")
            : String(localized: "Accept it in the EVE client before \(until); you pay \(price).")
    }
}
