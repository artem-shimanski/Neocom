import Foundation

// A character's industry jobs: `/characters/{id}/industry/jobs?include_completed=true`. Plain
// data, independent of the ESI types.

/// What a job does, from ESI's `activity_id`.
public enum IndustryActivity: String, Codable, Sendable, Hashable, CaseIterable {
    case manufacturing
    case researchTime
    case researchMaterial
    case copying
    case reverseEngineering
    case invention
    case reaction
    case unknown

    /// SDE / ESI activity ids. Reactions have used both 9 and 11 over the years.
    public init(activityID: Int) {
        switch activityID {
        case 1: self = .manufacturing
        case 3: self = .researchTime
        case 4: self = .researchMaterial
        case 5: self = .copying
        case 7: self = .reverseEngineering
        case 8: self = .invention
        case 9, 11: self = .reaction
        default: self = .unknown
        }
    }

    /// Research raises a blueprint by levels, copying makes copies, the rest runs: what a job's
    /// `runs` count is called.
    public var runUnit: RunUnit {
        switch self {
        case .researchTime, .researchMaterial: .levels
        case .copying: .copies
        default: .runs
        }
    }

    public enum RunUnit: String, Sendable, Hashable {
        case runs
        case levels
        case copies
    }
}

/// One industry job.
public struct IndustryJob: Codable, Sendable, Hashable, Identifiable {
    /// ESI's `status`, raw: `active`, `paused`, `ready`, `delivered`, `cancelled`, `reverted`.
    /// Read it through `phase(at:)`.
    public typealias Status = String

    /// The job id.
    public var id: Int64
    public var activityID: Int
    /// The blueprint's item id.
    public var blueprintID: Int64
    public var blueprintTypeID: Int64
    /// The hangar or container the blueprint was taken from.
    public var blueprintLocationID: Int64
    /// The hangar or container the output goes to.
    public var outputLocationID: Int64
    /// The facility (a station or a structure) the job runs in.
    public var facilityID: Int64
    /// The station or structure the facility is in.
    public var stationID: Int64
    public var installerID: Int64
    /// Who delivered or cancelled it.
    public var completedCharacterID: Int64?
    public var productTypeID: Int64?
    public var runs: Int
    /// Runs of each copy made (copying) or of each invented copy (invention).
    public var licensedRuns: Int?
    /// Invention only: after delivery, how many runs succeeded.
    public var successfulRuns: Int?
    /// Invention only: chance a run succeeds, 0…1.
    public var probability: Double?
    /// ISK.
    public var cost: Double?
    public var startDate: Date
    public var endDate: Date
    public var pauseDate: Date?
    public var completedDate: Date?
    /// Seconds.
    public var duration: Int64
    public var status: Status

    public init(id: Int64, activityID: Int, blueprintID: Int64 = 0, blueprintTypeID: Int64,
                blueprintLocationID: Int64 = 0, outputLocationID: Int64 = 0, facilityID: Int64 = 0,
                stationID: Int64 = 0, installerID: Int64 = 0, completedCharacterID: Int64? = nil,
                productTypeID: Int64? = nil, runs: Int, licensedRuns: Int? = nil, successfulRuns: Int? = nil,
                probability: Double? = nil, cost: Double? = nil, startDate: Date, endDate: Date,
                pauseDate: Date? = nil, completedDate: Date? = nil, duration: Int64? = nil, status: Status) {
        self.id = id
        self.activityID = activityID
        self.blueprintID = blueprintID
        self.blueprintTypeID = blueprintTypeID
        self.blueprintLocationID = blueprintLocationID
        self.outputLocationID = outputLocationID
        self.facilityID = facilityID
        self.stationID = stationID
        self.installerID = installerID
        self.completedCharacterID = completedCharacterID
        self.productTypeID = productTypeID
        self.runs = runs
        self.licensedRuns = licensedRuns
        self.successfulRuns = successfulRuns
        self.probability = probability
        self.cost = cost
        self.startDate = startDate
        self.endDate = endDate
        self.pauseDate = pauseDate
        self.completedDate = completedDate
        self.duration = duration ?? Int64(endDate.timeIntervalSince(startDate))
        self.status = status
    }
}

/// Where a job stands at a given moment. ESI keeps saying `active` after a job's end date
/// until it next recomputes; the clock says `ready` sooner.
public enum IndustryJobPhase: String, Codable, Sendable, Hashable {
    case ready
    case active
    case paused
    case delivered
    case cancelled
    case reverted
    case unknown

    /// Delivered, cancelled or reverted: nothing more will happen to it.
    public var isCompleted: Bool {
        switch self {
        case .delivered, .cancelled, .reverted: true
        default: false
        }
    }
}

extension IndustryJob {
    public var activity: IndustryActivity { IndustryActivity(activityID: activityID) }

    public func phase(at now: Date) -> IndustryJobPhase {
        switch status {
        case "ready": return .ready
        case "active": return endDate <= now ? .ready : .active
        case "paused": return .paused
        case "delivered": return .delivered
        case "cancelled": return .cancelled
        case "reverted": return .reverted
        default: return .unknown
        }
    }

    /// How far along the job is, 0…1: against the clock while it runs, frozen at the pause
    /// while paused, at the moment it was cancelled or reverted for those.
    public func progress(at now: Date) -> Double {
        switch phase(at: now) {
        case .ready, .delivered: return 1
        case .active: return fraction(at: now)
        case .paused: return pauseDate.map(fraction(at:)) ?? 0
        case .cancelled, .reverted: return completedDate.map(fraction(at:)) ?? 0
        case .unknown: return 0
        }
    }

    /// Time to the end: from now while active, from the pause while paused (what is left when
    /// it resumes). 0 otherwise.
    public func timeLeft(at now: Date) -> TimeInterval {
        switch phase(at: now) {
        case .active: return max(0, endDate.timeIntervalSince(now))
        case .paused: return max(0, endDate.timeIntervalSince(pauseDate ?? startDate))
        default: return 0
        }
    }

    /// Since the end, for a job that is ready.
    public func timeSinceEnd(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(endDate)) }

    private func fraction(at moment: Date) -> Double {
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0 else { return 1 }
        return min(1, max(0, moment.timeIntervalSince(startDate) / total))
    }
}

/// The figures of the industry screen's summary strip and of its tile.
public struct IndustrySummary: Sendable, Hashable {
    public var readyCount: Int
    public var activeCount: Int
    public var pausedCount: Int
    /// The soonest end of a job that is still running.
    public var nextCompletion: Date?

    public init(_ jobs: [IndustryJob], now: Date) {
        var ready = 0, active = 0, paused = 0
        var next: Date?
        for job in jobs {
            switch job.phase(at: now) {
            case .ready: ready += 1
            case .active:
                active += 1
                next = min(next ?? job.endDate, job.endDate)
            case .paused: paused += 1
            default: break
            }
        }
        readyCount = ready
        activeCount = active
        pausedCount = paused
        nextCompletion = next
    }
}

extension Array where Element == IndustryJob {
    /// The running jobs, soonest end first — the order of the `ACTIVE` list.
    public func activeSortedByEnd(at now: Date) -> [IndustryJob] {
        filter { $0.phase(at: now) == .active }.sorted { $0.endDate < $1.endDate }
    }

    /// The completed jobs, latest first (by completion, or end where there is none).
    public func completedLatestFirst(at now: Date) -> [IndustryJob] {
        filter { $0.phase(at: now).isCompleted }
            .sorted { ($0.completedDate ?? $0.endDate) > ($1.completedDate ?? $1.endDate) }
    }
}
