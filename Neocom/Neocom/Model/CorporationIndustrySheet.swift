import AssetsKit
import BusinessKit
import ESIKit
import Foundation
import Observation

/// A corporation's industry jobs, as seen by one of its characters.
///
/// The only owner of `/corporations/{id}/industry/jobs`, always called with
/// `include_completed`. Cached per viewing character, with the corporation id in the kind.
/// Nothing here reaches notifications or widgets.
@Observable
@MainActor
final class CorporationIndustrySheet {
    /// ESI's cache time for the route.
    private static let ttl: TimeInterval = 300

    /// The viewer.
    let characterID: Int64
    let boundCorporationID: Int64
    /// Whether the account was granted `esi-industry.read_corporation_jobs.v1`.
    let hasScope: Bool
    private(set) var snapshot: ESISnapshot<ESIIndustryJobs>

    var corporationID: Int64? { boundCorporationID }
    var value: ESIIndustryJobs? { snapshot.value }
    var fetchedAt: Date? { snapshot.fetchedAt }
    var state: ESISnapshot<ESIIndustryJobs>.State { snapshot.state }

    var access: BusinessAccess { .corporation(hasScope: hasScope, isForbidden: snapshot.state.isForbidden) }

    init(characterID: Int64, corporationID: Int64, client: Client, hasScope: Bool) {
        self.characterID = characterID
        self.boundCorporationID = corporationID
        self.hasScope = hasScope
        let memory = LookupMemory()
        snapshot = ESISnapshot(kind: "corp-\(corporationID)-industry-jobs", characterID: characterID, ttl: Self.ttl, cache: ESICache()) {
            let payload = try await ESIParallel.allPages { page in
                let answer = try await client.corporationIndustryJobs(corporationID: corporationID, includeCompleted: true, page: page)
                return (answer.jobs, answer.pages)
            }
            var seen: Set<Int64> = []
            let jobs = payload.map(IndustryJob.init).filter { seen.insert($0.id).inserted }
            async let locations = LookupMemory.locations(jobs.flatMap { [$0.facilityID, $0.stationID] },
                                                         memory: memory, client: client)
            async let names = LookupMemory.names(jobs.flatMap { [$0.installerID, $0.completedCharacterID ?? 0] },
                                                 memory: memory, client: client)
            return ESIIndustryJobs(jobs: jobs, locations: await locations, names: await names)
        }
        memory.seed(locations: snapshot.value?.locations ?? [:], names: snapshot.value?.names ?? [:])
    }

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

extension CorporationIndustrySheet: IndustrySource, CorporationBound {}

nonisolated extension IndustryJob {
    /// The corporation route names the station `location_id`.
    init(_ payload: Components.Schemas.CorporationsCorporationIdIndustryJobsGetPayload) {
        self.init(id: payload.jobId,
                  activityID: Int(payload.activityId),
                  blueprintID: payload.blueprintId,
                  blueprintTypeID: payload.blueprintTypeId,
                  blueprintLocationID: payload.blueprintLocationId,
                  outputLocationID: payload.outputLocationId,
                  facilityID: payload.facilityId,
                  stationID: payload.locationId,
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
