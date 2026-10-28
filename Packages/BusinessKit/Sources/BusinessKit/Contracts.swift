import Foundation

// A character's contracts: `/characters/{id}/contracts` (paged; outstanding and in progress,
// plus 30 days of finished ones) and, per contract, `/items` and `/bids`. Plain data,
// independent of the ESI types.

/// ESI's contract `type`.
public enum ContractKind: String, Codable, Sendable, Hashable, CaseIterable {
    case itemExchange = "item_exchange"
    case auction
    case courier
    case loan
    case unknown

    /// A raw value ESI adds later reads as `unknown`.
    public init(raw: String) { self = ContractKind(rawValue: raw) ?? .unknown }
}

/// ESI's contract `status`.
public enum ContractStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case outstanding
    case inProgress = "in_progress"
    case finishedIssuer = "finished_issuer"
    case finishedContractor = "finished_contractor"
    case finished
    case cancelled
    case rejected
    case failed
    case deleted
    case reversed
    case unknown

    public init(raw: String) { self = ContractStatus(rawValue: raw) ?? .unknown }

    /// Outstanding or in progress: the `Active` list.
    public var isActive: Bool { self == .outstanding || self == .inProgress }

    /// How the status reads: done well, done without effect, or gone wrong.
    public var tone: Tone {
        switch self {
        case .outstanding, .inProgress: .active
        case .finished, .finishedIssuer, .finishedContractor: .finished
        case .cancelled, .deleted, .unknown: .closed
        case .rejected, .failed, .reversed: .failed
        }
    }

    public enum Tone: Sendable, Hashable {
        case active
        case finished
        case closed
        case failed
    }
}

/// ESI's contract `availability`.
public enum ContractAvailability: String, Codable, Sendable, Hashable, CaseIterable {
    case `public`
    case personal
    case corporation
    case alliance
    case unknown

    public init(raw: String) { self = ContractAvailability(rawValue: raw) ?? .unknown }
}

/// One contract the character issued, was offered or accepted.
public struct Contract: Codable, Sendable, Hashable, Identifiable {
    /// The contract id.
    public var id: Int64
    /// Raw ESI strings — see `kind`, `status`, `availability`.
    public var type: String
    public var statusRaw: String
    public var availabilityRaw: String
    /// The issuer's own title; often empty.
    public var title: String?
    public var issuerID: Int64
    public var issuerCorporationID: Int64
    /// Who it is offered to (character, corporation or alliance); 0 for none.
    public var assigneeID: Int64
    /// Who accepted it; 0 for nobody yet.
    public var acceptorID: Int64
    /// Issued on behalf of the issuer's corporation.
    public var forCorporation: Bool
    public var dateIssued: Date
    public var dateExpired: Date
    public var dateAccepted: Date?
    public var dateCompleted: Date?
    /// Courier only.
    public var daysToComplete: Int?
    /// Exchange: the price; auction: the starting bid. ISK.
    public var price: Double?
    /// Courier only. ISK.
    public var reward: Double?
    /// Courier only. ISK.
    public var collateral: Double?
    /// Auction only. ISK.
    public var buyout: Double?
    /// m³.
    public var volume: Double?
    public var startLocationID: Int64?
    public var endLocationID: Int64?

    public init(id: Int64, type: String, status: String, availability: String = "public", title: String? = nil,
                issuerID: Int64, issuerCorporationID: Int64 = 0, assigneeID: Int64 = 0, acceptorID: Int64 = 0,
                forCorporation: Bool = false, dateIssued: Date, dateExpired: Date, dateAccepted: Date? = nil,
                dateCompleted: Date? = nil, daysToComplete: Int? = nil, price: Double? = nil, reward: Double? = nil,
                collateral: Double? = nil, buyout: Double? = nil, volume: Double? = nil,
                startLocationID: Int64? = nil, endLocationID: Int64? = nil) {
        self.id = id
        self.type = type
        self.statusRaw = status
        self.availabilityRaw = availability
        self.title = title
        self.issuerID = issuerID
        self.issuerCorporationID = issuerCorporationID
        self.assigneeID = assigneeID
        self.acceptorID = acceptorID
        self.forCorporation = forCorporation
        self.dateIssued = dateIssued
        self.dateExpired = dateExpired
        self.dateAccepted = dateAccepted
        self.dateCompleted = dateCompleted
        self.daysToComplete = daysToComplete
        self.price = price
        self.reward = reward
        self.collateral = collateral
        self.buyout = buyout
        self.volume = volume
        self.startLocationID = startLocationID
        self.endLocationID = endLocationID
    }
}

/// How a contract relates to the character looking at it.
public struct ContractRole: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let issuer = ContractRole(rawValue: 1 << 0)
    public static let assignee = ContractRole(rawValue: 1 << 1)
    public static let acceptor = ContractRole(rawValue: 1 << 2)
}

extension Contract {
    public var kind: ContractKind { ContractKind(raw: type) }
    public var status: ContractStatus { ContractStatus(raw: statusRaw) }
    public var availability: ContractAvailability { ContractAvailability(raw: availabilityRaw) }

    /// The roles `characterID` has in this contract.
    public func roles(of characterID: Int64) -> ContractRole {
        var roles: ContractRole = []
        if issuerID == characterID { roles.insert(.issuer) }
        if assigneeID != 0, assigneeID == characterID { roles.insert(.assignee) }
        if acceptorID != 0, acceptorID == characterID { roles.insert(.acceptor) }
        return roles
    }

    public func isIssued(by characterID: Int64) -> Bool { issuerID == characterID }

    /// Offered to `characterID` personally by someone else and still waiting for an answer —
    /// the summary's `TO YOU`.
    public func isOfferedTo(_ characterID: Int64) -> Bool {
        status == .outstanding && assigneeID == characterID && issuerID != characterID
    }

    /// An active contract someone else issued that waits on `characterID`: offered to them, or
    /// a courier they carry — the list's `FOR YOU` group. The rest of the active list is
    /// `ISSUED BY YOU`.
    public func isForMe(_ characterID: Int64) -> Bool {
        guard status.isActive, issuerID != characterID else { return false }
        return assigneeID == characterID || acceptorID == characterID
    }

    /// Issued on behalf of `corporationID` by one of its members.
    public func isIssuedByCorporation(_ corporationID: Int64) -> Bool {
        forCorporation && issuerCorporationID == corporationID
    }

    /// An active contract the corporation did not issue that waits on it: offered to it, or a
    /// courier it carries.
    public func isForCorporation(_ corporationID: Int64) -> Bool {
        guard status.isActive, !isIssuedByCorporation(corporationID) else { return false }
        return assigneeID == corporationID || acceptorID == corporationID
    }

    /// Courier only: when the package is due — `dateAccepted` plus `daysToComplete`.
    public var deadline: Date? {
        guard kind == .courier, let dateAccepted, let daysToComplete else { return nil }
        return dateAccepted.addingTimeInterval(TimeInterval(daysToComplete) * 86_400)
    }

    /// The moment an active contract is counting down to: the courier's deadline once
    /// accepted, the expiry otherwise. `nil` for a finished one.
    public var activeDue: Date? {
        switch status {
        case .inProgress: deadline ?? dateExpired
        case .outstanding: dateExpired
        default: nil
        }
    }

    /// Time to `activeDue`, never negative; 0 for a finished contract.
    public func timeLeft(at now: Date) -> TimeInterval {
        activeDue.map { max(0, $0.timeIntervalSince(now)) } ?? 0
    }

    /// Outstanding past its expiry: it stays listed until removed in game.
    public func isExpired(at now: Date) -> Bool { status == .outstanding && dateExpired <= now }

    /// A courier in progress past its deadline. ESI keeps it `in_progress` until it is settled
    /// in game.
    public func isOverdue(at now: Date) -> Bool {
        guard status == .inProgress, let deadline else { return false }
        return deadline <= now
    }

    /// Less than a day to `activeDue` and not past it.
    public func isDueSoon(at now: Date) -> Bool {
        guard let due = activeDue else { return false }
        let left = due.timeIntervalSince(now)
        return left > 0 && left < 86_400
    }

    /// The date a finished contract is listed under: its completion, or its expiry when it
    /// never completed.
    public var closedDate: Date { dateCompleted ?? dateExpired }

    /// Courier, failed: the courier missed the deadline — on the issuer's side the collateral
    /// was paid to them.
    public var courierFailed: Bool { kind == .courier && status == .failed }
}

/// The figures of the contracts screen's summary strip and of its tile.
public struct ContractsSummary: Sendable, Hashable {
    public var activeCount: Int
    public var finishedCount: Int
    public var outstandingCount: Int
    public var inProgressCount: Int
    /// Outstanding contracts offered to the character personally.
    public var toYouCount: Int

    public init(_ contracts: [Contract], characterID: Int64) {
        activeCount = contracts.filter { $0.status.isActive }.count
        finishedCount = contracts.count - activeCount
        outstandingCount = contracts.filter { $0.status == .outstanding }.count
        inProgressCount = contracts.filter { $0.status == .inProgress }.count
        toYouCount = contracts.filter { $0.isOfferedTo(characterID) }.count
    }

    /// The same figures for a corporation's contracts; `toYouCount` counts the outstanding
    /// ones assigned to the corporation.
    public init(_ contracts: [Contract], corporationID: Int64) {
        activeCount = contracts.filter { $0.status.isActive }.count
        finishedCount = contracts.count - activeCount
        outstandingCount = contracts.filter { $0.status == .outstanding }.count
        inProgressCount = contracts.filter { $0.status == .inProgress }.count
        toYouCount = contracts.filter {
            $0.status == .outstanding && $0.assigneeID == corporationID && !$0.isIssuedByCorporation(corporationID)
        }.count
    }
}

// MARK: - Items and bids

/// One line of `/contracts/{id}/items`.
public struct ContractItem: Codable, Sendable, Hashable, Identifiable {
    /// The record id.
    public var id: Int64
    public var typeID: Int64
    public var quantity: Int64
    /// `-1` for a blueprint original (or any singleton), `-2` for a blueprint copy.
    public var rawQuantity: Int64?
    /// `true`: the issuer gives it; `false`: the issuer asks for it.
    public var isIncluded: Bool
    public var isSingleton: Bool

    public init(id: Int64, typeID: Int64, quantity: Int64, rawQuantity: Int64? = nil,
                isIncluded: Bool = true, isSingleton: Bool = false) {
        self.id = id
        self.typeID = typeID
        self.quantity = quantity
        self.rawQuantity = rawQuantity
        self.isIncluded = isIncluded
        self.isSingleton = isSingleton
    }

    public var isBlueprintCopy: Bool { rawQuantity == -2 }
}

/// One bid of `/contracts/{id}/bids`.
public struct ContractBid: Codable, Sendable, Hashable, Identifiable {
    /// The bid id.
    public var id: Int64
    public var bidderID: Int64
    /// ISK.
    public var amount: Double
    public var date: Date

    public init(id: Int64, bidderID: Int64, amount: Double, date: Date) {
        self.id = id
        self.bidderID = bidderID
        self.amount = amount
        self.date = date
    }
}

extension Array where Element == ContractBid {
    /// Highest first; among equal amounts the earlier bid first (it was there first).
    public var highestFirst: [ContractBid] {
        sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.date < $1.date }
    }

    public var highest: ContractBid? { highestFirst.first }
}

extension Contract {
    /// Auction only: where the high bid sits between the starting price and the buyout, 0…1.
    /// With no bids the starting price counts; `nil` without a buyout above the start.
    public func auctionProgress(highBid: Double?) -> Double? {
        guard kind == .auction, let start = price, let buyout, buyout > start else { return nil }
        let high = highBid ?? start
        return Swift.min(1, Swift.max(0, (high - start) / (buyout - start)))
    }
}
