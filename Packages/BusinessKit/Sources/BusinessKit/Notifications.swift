import Foundation

// Notification inputs as plain data: moments known in advance (an industry job's end, a contract's
// expiry or courier deadline) and changes found by a background check against a stored baseline
// (an order filled or expired, a contract finished).

// MARK: - Known moments

public enum IndustryReminders {
    /// The jobs to be told about: running, ending after `now`, soonest first.
    public static func plan(_ jobs: [IndustryJob], now: Date) -> [IndustryJob] {
        jobs.filter { $0.phase(at: now) == .active && $0.endDate > now }
            .sorted { ($0.endDate, $0.id) < ($1.endDate, $1.id) }
    }
}

/// One contract moment ahead: the expiry of an outstanding contract, or a courier's deadline.
public struct ContractReminder: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case expires
        case courierDue
    }

    public var contract: Contract
    public var kind: Kind
    /// The event less `ContractReminders.lead`.
    public var fireDate: Date
    public var eventDate: Date

    public var id: String { "\(kind.rawValue).\(contract.id)" }

    public init(contract: Contract, kind: Kind, fireDate: Date, eventDate: Date) {
        self.contract = contract
        self.kind = kind
        self.fireDate = fireDate
        self.eventDate = eventDate
    }
}

public enum ContractReminders {
    /// How long before the moment the reminder goes off: "about to expire".
    public static let lead: TimeInterval = 3600

    /// The outstanding contracts `characterID` issued or was offered, before they expire, and
    /// the couriers they issued or carry, before the deadline — soonest first. Moments whose
    /// reminder would already be past are left out.
    public static func plan(_ contracts: [Contract], characterID: Int64, now: Date) -> [ContractReminder] {
        plan(contracts, now: now,
             expires: { $0.isIssued(by: characterID) || $0.isOfferedTo(characterID) },
             courierDue: { $0.isIssued(by: characterID) || $0.acceptorID == characterID })
    }

    /// The same moments for a corporation: the outstanding contracts it issued or was offered,
    /// and the couriers it issued or carries.
    public static func plan(_ contracts: [Contract], corporationID: Int64, now: Date) -> [ContractReminder] {
        plan(contracts, now: now,
             expires: { $0.isIssuedByCorporation(corporationID) || $0.assigneeID == corporationID },
             courierDue: { $0.isIssuedByCorporation(corporationID) || $0.acceptorID == corporationID })
    }

    private static func plan(_ contracts: [Contract], now: Date, expires: (Contract) -> Bool,
                             courierDue: (Contract) -> Bool) -> [ContractReminder] {
        var reminders: [ContractReminder] = []
        for contract in contracts {
            switch contract.status {
            case .outstanding:
                guard expires(contract) else { continue }
                reminders.append(ContractReminder(contract: contract, kind: .expires,
                                                  fireDate: contract.dateExpired.addingTimeInterval(-lead),
                                                  eventDate: contract.dateExpired))
            case .inProgress:
                guard let deadline = contract.deadline, courierDue(contract) else { continue }
                reminders.append(ContractReminder(contract: contract, kind: .courierDue,
                                                  fireDate: deadline.addingTimeInterval(-lead), eventDate: deadline))
            default:
                continue
            }
        }
        return reminders
            .filter { $0.fireDate > now }
            .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    }
}

// MARK: - Changes since the last check

public enum OrderWatch {
    /// The open orders' ids as last seen; `nil` before the first check.
    public typealias Baseline = Set<Int64>

    /// The orders that were open at the last check and have since been filled or expired, and
    /// the baseline for the next check.
    ///
    /// Without a baseline nothing is reported: the first check only records what is open.
    /// An order that left the open list but is not in the history yet stays in the baseline —
    /// the history is cached longer than the open list — and is reported once it appears there.
    /// A cancelled one is dropped without a word: the player did that themselves.
    public static func check(open: [CharacterOrder], history: [CharacterOrder],
                             baseline: Baseline?) -> (closed: [CharacterOrder], baseline: Baseline) {
        let openIDs = Set(open.map(\.id))
        guard let baseline else { return ([], openIDs) }
        let historyByID = Dictionary(history.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var closed: [CharacterOrder] = []
        var next = openIDs
        for id in baseline.subtracting(openIDs) {
            guard let order = historyByID[id] else {
                next.insert(id)
                continue
            }
            if order.outcome == .filled || order.outcome == .expired { closed.append(order) }
        }
        return (closed.sorted { $0.id < $1.id }, next)
    }
}

public enum ContractWatch {
    /// The statuses of the active contracts the character has a part in, as last seen; `nil`
    /// before the first check.
    public typealias Baseline = [Int64: String]

    /// The contracts that were active at the last check and have since finished — completed,
    /// or gone wrong (rejected, failed, reversed) — and the baseline for the next check.
    /// Without a baseline nothing is reported. Cancelled and deleted ones are the player's own
    /// doing and say nothing.
    public static func check(_ contracts: [Contract], characterID: Int64,
                             baseline: Baseline?) -> (finished: [Contract], baseline: Baseline) {
        check(contracts.filter { !$0.roles(of: characterID).isEmpty }, baseline: baseline)
    }

    /// The same for a corporation: the contracts it issued, was assigned or accepted.
    public static func check(_ contracts: [Contract], corporationID: Int64,
                             baseline: Baseline?) -> (finished: [Contract], baseline: Baseline) {
        let ours = contracts.filter {
            $0.isIssuedByCorporation(corporationID) || $0.assigneeID == corporationID || $0.acceptorID == corporationID
        }
        return check(ours, baseline: baseline)
    }

    private static func check(_ mine: [Contract], baseline: Baseline?) -> (finished: [Contract], baseline: Baseline) {
        let next = Dictionary(mine.filter { $0.status.isActive }.map { ($0.id, $0.statusRaw) },
                              uniquingKeysWith: { first, _ in first })
        guard let baseline else { return ([], next) }
        let finished = mine.filter { contract in
            guard let was = baseline[contract.id], ContractStatus(raw: was).isActive else { return false }
            return contract.status.tone == .finished || contract.status.tone == .failed
        }
        return (finished.sorted { $0.id < $1.id }, next)
    }
}
