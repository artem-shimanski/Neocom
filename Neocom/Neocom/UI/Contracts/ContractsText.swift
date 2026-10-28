import AssetsKit
import BusinessKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

// What the Contracts screens say about a contract, in one place: the list row and the three
// detail layouts print a kind, a state, a party or a place the same way.

/// Wording and colour of the contract fields that more than one screen prints.
enum ContractText {
    static func kindTitle(_ kind: ContractKind) -> String {
        switch kind {
        case .itemExchange: String(localized: "Item Exchange")
        case .auction: String(localized: "Auction")
        case .courier: String(localized: "Courier")
        case .loan: String(localized: "Loan")
        case .unknown: String(localized: "Unknown Type")
        }
    }

    static func symbol(_ kind: ContractKind) -> String {
        switch kind {
        case .itemExchange: "arrow.left.arrow.right"
        case .auction: "hammer"
        case .courier: "shippingbox"
        case .loan: "arrow.uturn.backward.circle"
        case .unknown: "questionmark.square.dashed"
        }
    }

    static func availabilityTitle(_ availability: ContractAvailability) -> String {
        switch availability {
        case .public: String(localized: "Public")
        case .personal: String(localized: "Personal")
        case .corporation: String(localized: "Corporation")
        case .alliance: String(localized: "Alliance")
        case .unknown: String(localized: "Unknown")
        }
    }

    /// `OUTSTANDING`, `IN PROGRESS`, … — and `EXPIRED` for an outstanding contract past its
    /// expiry, which stays listed until it is removed in game.
    static func state(of contract: Contract, now: Date) -> String {
        if contract.isExpired(at: now) { return String(localized: "Expired") }
        if contract.isOverdue(at: now) { return String(localized: "Overdue") }
        return switch contract.status {
        case .outstanding: String(localized: "Outstanding")
        case .inProgress: String(localized: "In Progress")
        case .finishedIssuer: String(localized: "Finished · Issuer")
        case .finishedContractor: String(localized: "Finished · Contractor")
        case .finished: String(localized: "Finished")
        case .cancelled: String(localized: "Cancelled")
        case .deleted: String(localized: "Deleted")
        case .rejected: String(localized: "Rejected")
        case .failed: String(localized: "Failed")
        case .reversed: String(localized: "Reversed")
        case .unknown: String(localized: "Unknown")
        }
    }

    static func stateColor(of contract: Contract, now: Date) -> Color {
        if contract.isExpired(at: now) || contract.isOverdue(at: now) { return .hudWarn }
        return switch contract.status.tone {
        case .active: .hudAccent
        case .finished: .hudOk
        case .closed: .hudInkMuted
        case .failed: .hudDanger
        }
    }

    /// `28 400 m³`.
    static func volume(_ value: Double) -> String { FitStatFormat.m³(value) }

    static func quantity(_ value: Int64) -> String { "×\(value.formatted(.number))" }

    /// `1 250 000 ISK`, whole ISK: a contract's price is never in cents.
    static func isk(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)))) ISK"
    }
}

/// Everything a screen needs to name the parties and places of the contracts it shows, and the
/// view of the character that is looking.
struct ContractContext {
    var characterID: Int64
    var names: [Int64: ESIEntityName]
    var locations: [Int64: AssetLocationInfo]
    var places: ContractPlaces
    /// Set when the contracts are a corporation's.
    var corporationID: Int64?

    func name(of id: Int64) -> String? {
        id == 0 ? nil : names[id]?.name
    }

    /// The name to write for a party: `You` for the pilot.
    func partyName(_ id: Int64) -> String {
        if id == characterID { return String(localized: "You") }
        if id == corporationID { return name(of: id) ?? String(localized: "Corporation") }
        return name(of: id) ?? String(localized: "Unknown")
    }

    /// The solar system of a station or structure the contract names.
    func systemID(of locationID: Int64?) -> Int64? {
        guard let locationID else { return nil }
        return locations[locationID]?.solarSystemID
    }

    func system(of locationID: Int64?) -> MarketSystemRow? {
        systemID(of: locationID).flatMap { places.systems[$0] }
    }

    func locationName(_ locationID: Int64?) -> String {
        guard let locationID, let info = locations[locationID] else { return String(localized: "Unknown Location") }
        if let name = info.name { return name }
        return info.kind == .structureNoAccess
            ? String(localized: "Structure without access")
            : String(localized: "Unknown Location")
    }

    /// What the list calls a contract: the issuer's title, or — for a courier — its route, or
    /// the kind.
    func title(of contract: Contract) -> String {
        if let title = contract.title, !title.isEmpty { return title }
        guard contract.kind == .courier else { return ContractText.kindTitle(contract.kind) }
        let from = system(of: contract.startLocationID)?.name
        let to = system(of: contract.endLocationID)?.name
        var text = [from, to].compactMap { $0 }.joined(separator: " → ")
        if from == nil || to == nil { text = ContractText.kindTitle(.courier) }
        if let volume = contract.volume { text += " · \(ContractText.volume(volume))" }
        return text
    }

    /// `BY YOU · TOVI SALTMARSH`, `FROM OSKAR TIDEWATER`, `YOU CARRIED · FOR BRAM IRONVALE`.
    func party(of contract: Contract) -> String {
        if let corporationID, contract.isIssuedByCorporation(corporationID) {
            var text = String(localized: "By \(partyName(contract.issuerID))")
            if contract.acceptorID != 0, let name = name(of: contract.acceptorID) {
                text += " · \(name)"
            } else if contract.availability != .public, let name = name(of: contract.assigneeID) {
                text += " · " + String(localized: "to \(name)")
            }
            return text
        }
        if corporationID == nil, contract.isIssued(by: characterID) {
            var text = String(localized: "By you")
            if contract.acceptorID != 0, let name = name(of: contract.acceptorID) {
                text += " · \(name)"
            } else if contract.availability != .public, let name = name(of: contract.assigneeID) {
                text += " · " + String(localized: "to \(name)")
            }
            return text
        }
        let issuer = partyName(contract.issuerID)
        if contract.kind == .courier, contract.acceptorID == characterID {
            return contract.status.isActive
                ? String(localized: "From \(issuer) · you carry")
                : String(localized: "You carried · for \(issuer)")
        }
        return String(localized: "From \(issuer)")
    }

    /// Who the contract is offered to: `Public`, `Personal · <PILOT>`.
    func availableTo(_ contract: Contract) -> String {
        let title = ContractText.availabilityTitle(contract.availability)
        guard contract.availability != .public, let name = name(of: contract.assigneeID) else { return title }
        return "\(title) · \(name)"
    }
}

/// The static data rows the screens look up: systems with their region, and types.
struct ContractPlaces {
    var systems: [Int64: MarketSystemRow] = [:]
    var types: [Int64: AssetTypeRow] = [:]
}

/// Reads systems and types out of the SDE and hands them over as `ContractPlaces`.
struct ContractPlacesReader<Content: View>: View {
    @LiteQuery private var systemRows: [MarketSystemRow]
    @LiteQuery private var typeRows: [AssetTypeRow]
    private let content: (ContractPlaces) -> Content

    init(systemIDs: some Sequence<Int64>, typeIDs: some Sequence<Int64>,
         @ViewBuilder content: @escaping (ContractPlaces) -> Content) {
        self.content = content
        let systems = Array(Set(systemIDs)).sorted().map(MarketFormat.systemID)
        let types = Array(Set(typeIDs)).sorted().map { TypeID(rawValue: UInt32(clamping: $0)) }
        _systemRows = LiteQuery(systems.isEmpty ? nil : MarketBrowser.systems(systems))
        _typeRows = LiteQuery(types.isEmpty ? nil : AssetsBrowser.types(types))
    }

    var body: some View {
        content(ContractPlaces(
            systems: Dictionary(systemRows.map { (Int64($0.id.rawValue), $0) }, uniquingKeysWith: { first, _ in first }),
            types: Dictionary(typeRows.map { (Int64($0.id.rawValue), $0) }, uniquingKeysWith: { first, _ in first })))
    }
}

/// `RENS 0.9 · HEIMATAR · 2 J FROM OSOGGUR`, the second line of a place.
func contractSystemLine(_ system: MarketSystemRow?, jumps: String? = nil) -> Text? {
    guard let system else { return nil }
    return HUDPlaceBlock.line(systemName: system.name, security: system.securityStatus,
                              details: [system.regionName, jumps])
}
