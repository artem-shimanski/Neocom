import ESIKit
import Foundation
import Observation
import SDEKit
import TrainingKit

/// One character's ESI data, in two snapshots: training (attributes, implants, skills, skill
/// queue) and profile (identity, wallet, location, ship, clones).
///
/// The only owner of the per-character profile and training routes. The snapshots are separate
/// because they have different TTLs and consumers: training data is used app-wide, the profile
/// only by the Character Sheet.
@Observable
@MainActor
final class CharacterSheet {
    typealias State = ESISnapshot<CharacterSnapshot>.State

    /// The shortest of the four routes' cache times (`/skills`, `/skillqueue`: 60 s;
    /// `/attributes`, `/implants`: 120 s).
    private static let trainingTTL: TimeInterval = 60

    nonisolated static let trainingCacheKind = "sheet"
    nonisolated static let profileCacheKind = "profile"

    /// The cache time of `/wallet` and `/clones`. `/location` and `/ship` are cached for only
    /// 5 s, but are not worth refetching that often.
    private static let profileTTL: TimeInterval = 120

    @ObservationIgnored private let training: ESISnapshot<CharacterSnapshot>
    @ObservationIgnored private let profileSnapshot: ESISnapshot<CharacterProfile>

    /// The last `Pilot` built by `pilot(using:)` and its inputs. `revision` changes only when
    /// the snapshot is replaced; the catalog is compared by its dictionaries, which is cheap when
    /// they share storage.
    @ObservationIgnored private var cachedPilot: (revision: Int, catalog: SkillCatalog, pilot: Pilot)?

    /// Used by `pilot(using:)` before any data has arrived.
    private static let emptySnapshot = CharacterSnapshot(
        attributes: CharacterAttributes(),
        implants: [],
        skills: [],
        queue: [],
        totalSkillPoints: 0
    )

    // MARK: - Training

    var snapshot: CharacterSnapshot? { training.value }
    var fetchedAt: Date? { training.fetchedAt }
    var state: State { training.state }
    var revision: Int { training.revision }

    // MARK: - Profile

    var profile: CharacterProfile? { profileSnapshot.value }
    var profileFetchedAt: Date? { profileSnapshot.fetchedAt }
    var profileState: ESISnapshot<CharacterProfile>.State { profileSnapshot.state }

    // `cache` defaults to `nil` so the default instance is created on the main actor.
    init(characterID: Int64, client: Client, cache: ESICache? = nil) {
        let cache = cache ?? ESICache()

        training = ESISnapshot(kind: Self.trainingCacheKind,
                               characterID: characterID,
                               ttl: Self.trainingTTL,
                               cache: cache) {
            async let attributes = client.characterAttributes(id: characterID)
            async let implants = client.characterImplants(id: characterID)
            async let skills = client.characterSkills(id: characterID)
            async let queue = client.characterSkillQueue(id: characterID)

            return try await CharacterSnapshot(
                attributes: attributes,
                implants: implants,
                skills: skills,
                queue: queue
            )
        }

        profileSnapshot = ESISnapshot(kind: Self.profileCacheKind,
                                      characterID: characterID,
                                      ttl: Self.profileTTL,
                                      cache: cache) {
            try await CharacterProfile.load(characterID: characterID, client: client)
        }

        // A new queue reschedules the training notifications and updates the widgets.
        training.didUpdate = { _ in
            NotificationPlanner.shared.reschedule(.training, characterID: characterID)
            WidgetSnapshotWriter.shared.setNeedsUpdate()
        }
        // A move to another corporation moves its notifications.
        profileSnapshot.didUpdate = { profile in
            NotificationPlanner.shared.corporationSeen(profile.corporationID, characterID: characterID)
        }
    }

    /// Refreshes the training snapshot if missing or past its TTL.
    func ensureFresh() async {
        await training.ensureFresh()
    }

    /// Refreshes the profile if missing or past its TTL.
    func ensureProfileFresh() async {
        await profileSnapshot.ensureFresh()
    }

    /// Cancels the fetches in flight and stops all disk writes; called by `AccountStore`.
    func invalidate() {
        training.invalidate()
        profileSnapshot.invalidate()
    }

    // MARK: - Location

    /// Maximum profile age accepted by `ensureLocationKnown()`.
    private static let locationTolerance: TimeInterval = 600

    /// The character's solar system as of the last profile fetch; `nil` before the first one.
    var currentSolarSystemID: Int64? {
        profile?.location?.solarSystemID.map { Int64($0.rawValue) }
    }

    /// Refreshes the profile only when it is missing or older than `locationTolerance`; for
    /// screens other than the Character Sheet that need `currentSolarSystemID`.
    func ensureLocationKnown() async {
        if let fetchedAt = profileFetchedAt, Date.now.timeIntervalSince(fetchedAt) < Self.locationTolerance {
            return
        }
        await profileSnapshot.ensureFresh()
    }

    /// Reloads both snapshots in parallel, ignoring their TTLs.
    func refresh() async {
        let training = training
        let profile = profileSnapshot
        async let trainingDone: Void = training.refresh()
        async let profileDone: Void = profile.refresh()
        _ = await (trainingDone, profileDone)
    }

    /// The current snapshot as a `Pilot`, memoized on `revision` and the catalog. Cheap enough
    /// to call from `body`.
    func pilot(using catalog: SkillCatalog) -> Pilot {
        if let cachedPilot,
           cachedPilot.revision == revision,
           cachedPilot.catalog.skills == catalog.skills,
           cachedPilot.catalog.implantBonuses == catalog.implantBonuses {
            return cachedPilot.pilot
        }

        let pilot = Pilot(snapshot: snapshot ?? Self.emptySnapshot, catalog: catalog, now: .now)
        cachedPilot = (revision, catalog, pilot)
        return pilot
    }
}
