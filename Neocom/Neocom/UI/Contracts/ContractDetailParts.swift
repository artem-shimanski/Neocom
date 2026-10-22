import BusinessKit
import SDEKit
import SwiftUI

// The pieces the three detail layouts share: the header card's bar and figures, the item
// sections, the location, and the facts panels.

/// What a layout draws a contract from.
struct ContractDetail {
    var contract: Contract
    var context: ContractContext
    var items: ESISnapshot<[ContractItem]>
    var bids: ESISnapshot<ESIContractBids>?
    var now: Date
    var pilotSystemID: Int64?
    var market: MarketSheet

    var me: Int64 { context.characterID }
    var isMine: Bool { contract.isIssued(by: me) }
    var isActive: Bool { contract.status.isActive }
    var isDueSoon: Bool { contract.isDueSoon(at: now) }

    /// `<PILOT>` for the pilot: the name ESI gave, `You` when it did not.
    func name(_ id: Int64) -> String { context.name(of: id) ?? context.partyName(id) }

    /// `—` for a missing date.
    func date(_ date: Date?) -> String { date.map(EVETime.dateTime) ?? "—" }

    /// The wording of a gate-jump count from the pilot's system: `2 J FROM OSOGGUR`, `HERE`.
    func jumpsFromPilot(to systemID: Int64?) -> String? {
        guard let pilot = pilotSystemID, let systemID, let count = market.jumps(from: pilot, to: systemID) else { return nil }
        if count == 0 { return String(localized: "Here").uppercased() }
        guard let origin = context.places.systems[pilot] else { return MarketFormat.jumps(count) }
        return String(localized: "\(MarketFormat.jumps(count)) from \(origin.name)").uppercased()
    }
}

// MARK: - Header card

extension ContractDetail {
    /// The strip over the card: the kind and who may take it, and where it stands.
    var headerBar: some View {
        HUDPanelHeader(title: Text("\(Image(systemName: ContractText.symbol(contract.kind)))  \(ContractText.kindTitle(contract.kind)) · \(ContractText.availabilityTitle(contract.availability))")) {
            HUDStatusChip(text: Text(verbatim: ContractText.state(of: contract, now: now)),
                          color: ContractText.stateColor(of: contract, now: now), mark: .dot)
        }
    }

    /// The border of the card: `warn` for something offered to the pilot that is about to lapse.
    var cardTone: HUDTone {
        if contract.status == .outstanding && !isMine && isDueSoon { return .warn }
        // A package the pilot carries that is due within a day, or already late.
        if contract.status == .inProgress, contract.acceptorID == me,
           isDueSoon || contract.isOverdue(at: now) { return .warn }
        return .normal
    }

    /// The line of text under the figures, in the colour of its urgency.
    func note(_ text: String, color: Color = .hudInkMuted) -> some View {
        HUDWarnNote(verbatim: text).colors(ink: color, background: .clear)
    }

    /// The countdown cell: time to `activeDue`, red-amber under a day, `Expired` past it.
    var timeLeftFigure: (text: String, color: Color) {
        if contract.isExpired(at: now) { return (String(localized: "Expired"), .hudWarn) }
        if contract.isOverdue(at: now) { return (String(localized: "Overdue"), .hudDanger) }
        return (EVETime.duration(contract.timeLeft(at: now)), isDueSoon ? .hudWarn : .hudInk)
    }
}

/// The three-figure strip of a header card.
func contractStrip(_ cells: [(label: Text, value: String, color: Color)]) -> some View {
    HUDStatStrip(items: cells.enumerated().map { index, cell in
        .init(id: index, label: cell.label, value: Text(verbatim: cell.value), color: cell.color)
    })
}

/// The title and the party line of a header card.
struct ContractTitleBlock: View {
    let title: String
    let party: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.hudCardTitle)
                .tracking(0.5)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: party.uppercased())
                .font(.hudCaption)
                .foregroundStyle(Color.hudInkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HUDMetrics.gutter)
        .padding(.vertical, 14)
    }
}

// MARK: - Items

/// A contract's items, or what stands where they would be: the spinner while they load, the
/// reason they did not. `included` picks the side of an exchange; `nil` takes all of them.
struct ContractItemsSection: View {
    let detail: ContractDetail
    let title: Text
    var included: Bool? = true
    /// The volume to write at the right of the header.
    var volume: Double?
    /// Whether a line says how much room it takes (the courier's package).
    var showsVolume = false

    var body: some View {
        let snapshot = detail.items
        if let all = snapshot.value {
            let rows = all.filter { included == nil || $0.isIncluded == included }
            if !rows.isEmpty {
                HUDListSection(rows, row: { item in
                    NavigationLink(value: DatabaseRoute.type(TypeID(rawValue: UInt32(clamping: item.typeID)))) {
                        ContractItemRow(item: item, places: detail.context.places, showsVolume: showsVolume)
                    }
                    .hudRowButton(HUDTypeRow.rowStyle)
                    .hudTypeContextMenu(typeID: item.typeID,
                                        name: detail.context.places.types[item.typeID]?.name ?? "")
                }, header: {
                    header(count: rows.count)
                })
            } else if included != false {
                // An exchange may ask for nothing: only the side that is there gets a card.
                Section {
                    Text("No items listed.")
                        .font(.hudCaption)
                        .foregroundStyle(Color.hudInkMuted)
                        .hudBareRow()
                } header: {
                    header(count: 0).hudListHeader()
                }
            }
        } else if included != false {
            Section {
                status(snapshot)
                    .hudBareRow()
            } header: {
                header(count: nil).hudListHeader()
            }
        }
    }

    private func header(count: Int?) -> some View {
        HUDSectionHeader(count.map { Text("\(title) · \($0)") } ?? title) {
            if let volume {
                Text(verbatim: ContractText.volume(volume))
            }
        }
    }

    @ViewBuilder
    private func status(_ snapshot: ESISnapshot<[ContractItem]>) -> some View {
        if case let .failed(error) = snapshot.state {
            HUDEmptyPanel(systemImage: "exclamationmark.triangle", title: Text("Items Unavailable"),
                          message: Text(error.localizedDescription))
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }
}

/// One item line: icon, name, `COPY · REC 123`, and the quantity.
private struct ContractItemRow: View {
    let item: ContractItem
    let places: ContractPlaces
    let showsVolume: Bool

    var body: some View {
        let row = places.types[item.typeID]
        let name = row?.name ?? String(localized: "Type \(item.typeID)")
        HUDTypeRow(typeID: TypeID(rawValue: UInt32(clamping: item.typeID)), name: name,
                   subtitle: Text(verbatim: subtitle(name: name, volume: row?.volume)),
                   quantity: Text(verbatim: ContractText.quantity(item.quantity)),
                   iconSize: 36, lineLimit: 1)
    }

    private func subtitle(name: String, volume: Double?) -> String {
        var parts: [String] = []
        if let chip = chip(name: name) { parts.append(chip) }
        if showsVolume, !item.isSingleton, let volume {
            parts.append(ContractText.volume(volume * Double(item.quantity)))
        }
        parts.append(String(localized: "REC \(item.id)", comment: "Record id of a contract item"))
        return parts.joined(separator: " · ")
    }

    /// A copy says so; a singleton is an original blueprint or an assembled item.
    private func chip(name: String) -> String? {
        if item.isBlueprintCopy { return String(localized: "Copy") }
        guard item.isSingleton else { return nil }
        return name.hasSuffix("Blueprint") ? String(localized: "Original") : String(localized: "Assembled")
    }
}

// MARK: - Location

/// A station or structure with its system, security, region and the jumps to it.
struct ContractLocationSection: View {
    let detail: ContractDetail
    let title: LocalizedStringKey
    let locationID: Int64?

    var body: some View {
        let context = detail.context
        let system = context.system(of: locationID)
        HUDListSection(title) {
            HUDPlaceBlock(name: context.locationName(locationID),
                          line: contractSystemLine(system, jumps: detail.jumpsFromPilot(to: context.systemID(of: locationID))))
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 12))
        }
    }
}

// MARK: - Facts

/// One line of a facts panel.
struct ContractFact {
    var label: LocalizedStringKey
    var value: String
    var color: Color = .hudInk
}

struct ContractFactsSection: View {
    let title: LocalizedStringKey
    let facts: [ContractFact]

    var body: some View {
        HUDListSection(title) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                HUDReadoutRow(Text(fact.label)) {
                    Text(verbatim: fact.value).foregroundStyle(fact.color)
                }
            }
        }
    }
}

extension ContractDetail {
    /// The PARTIES panel: who issued, for whom, to whom, and the one line each kind adds.
    func parties(last: ContractFact) -> ContractFactsSection {
        let c = contract
        return ContractFactsSection(title: "Parties", facts: [
            .init(label: "Issuer", value: name(c.issuerID)),
            .init(label: "Issuer Corp", value: context.name(of: c.issuerCorporationID) ?? "—"),
            .init(label: "On Behalf Of", value: c.forCorporation ? String(localized: "Corporation") : String(localized: "Issuer")),
            .init(label: "Available To", value: context.availableTo(c)),
            last,
        ])
    }

    /// `—` or the name of whoever accepted.
    var acceptor: String {
        contract.acceptorID == 0 ? "—" : name(contract.acceptorID)
    }

    var contractID: ContractFact { .init(label: "Contract ID", value: "\(contract.id)") }
}
