import AssetsKit
import BusinessKit
import ESIKit
import Foundation
import Observation

/// A character's industry jobs (running and 90 days of completed) as stored in `ESICache`, with
/// facilities and pilot names resolved.
nonisolated struct ESIIndustryJobs: Codable, Sendable, Hashable {
    var jobs: [IndustryJob]
    /// Names of the `facilityID`s and `stationID`s of `jobs` that could be resolved.
    var locations: [Int64: AssetLocationInfo]
    /// Names of the `installerID`s and `completedCharacterID`s of `jobs` that could be resolved.
    var names: [Int64: ESIEntityName]
}

/// A character's industry jobs.
///
/// The only owner of `/characters/{id}/industry/jobs`, always called with `include_completed`.
/// Job phases are derived from the clock, not from the next fetch.
@Observable
@MainActor
final class IndustrySheet {
    /// ESI's cache time for the route.
    private static let ttl: TimeInterval = 300

    nonisolated static let cacheKind = "industry-jobs"

    let characterID: Int64
    /// Whether the account was granted `esi-industry.read_character_jobs.v1`.
    let hasScope: Bool
    private(set) var snapshot: ESISnapshot<ESIIndustryJobs>

    var value: ESIIndustryJobs? { snapshot.value }
    var fetchedAt: Date? { snapshot.fetchedAt }
    var state: ESISnapshot<ESIIndustryJobs>.State { snapshot.state }

    init(characterID: Int64, client: Client, hasScope: Bool) {
        self.characterID = characterID
        self.hasScope = hasScope
        let memory = LookupMemory()
        snapshot = ESISnapshot(kind: Self.cacheKind, characterID: characterID, ttl: Self.ttl, cache: ESICache()) {
            let payload = try await client.industryJobs(characterID: characterID, includeCompleted: true)
            let jobs = payload.map(IndustryJob.init)
            async let locations = LookupMemory.locations(jobs.flatMap { [$0.facilityID, $0.stationID] },
                                                         memory: memory, client: client)
            async let names = LookupMemory.names(jobs.flatMap { [$0.installerID, $0.completedCharacterID ?? 0] },
                                                 memory: memory, client: client)
            return ESIIndustryJobs(jobs: jobs, locations: await locations, names: await names)
        }
        memory.seed(locations: snapshot.value?.locations ?? [:], names: snapshot.value?.names ?? [:])
        // A new job list reschedules the job-completion notifications.
        snapshot.didUpdate = { _ in
            NotificationPlanner.shared.reschedule(.industry, characterID: characterID)
        }
    }

    /// The account lacks the scope, or ESI answered `403`.
    var isMissingScope: Bool { !hasScope || snapshot.state.isForbidden }

    /// Refreshes the jobs if missing or past the TTL.
    func ensureFresh() async {
        guard hasScope else { return }
        await snapshot.ensureFresh()
    }

    func refresh() async {
        guard hasScope else { return }
        await snapshot.refresh()
    }

    /// Stops all disk writes; called by `AccountStore` when it drops the sheet.
    func invalidate() {
        snapshot.invalidate()
    }
}

nonisolated extension IndustryJob {
    init(_ payload: Components.Schemas.CharactersCharacterIdIndustryJobsGetPayload) {
        self.init(id: payload.jobId,
                  activityID: Int(payload.activityId),
                  blueprintID: payload.blueprintId,
                  blueprintTypeID: payload.blueprintTypeId,
                  blueprintLocationID: payload.blueprintLocationId,
                  outputLocationID: payload.outputLocationId,
                  facilityID: payload.facilityId,
                  stationID: payload.stationId,
                  installerID: payload.installerId,
                  completedCharacterID: payload.completedCharacterId,
                  productTypeID: payload.productTypeId,
                  runs: Int(payload.runs),
                  licensedRuns: payload.licensedRuns.map(Int.init),
                  successfulRuns: payload.successfulRuns.map(Int.init),
                  probability: payload.probability,
                  cost: payload.cost,
                  startDate: payload.startDate,
                  endDate: payload.endDate,
                  pauseDate: payload.pauseDate,
                  completedDate: payload.completedDate,
                  duration: payload.duration,
                  status: payload.status.rawValue)
    }
}
