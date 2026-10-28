import AssetsKit
import ESIKit
import Foundation
import Observation

/// A corporation's assets, as seen by one of its characters.
///
/// The only owner of `/corporations/{id}/assets` and `/corporations/{id}/assets/names`. Cached
/// per viewing character, with the corporation id in the kind. Nothing here reaches
/// notifications or widgets.
@Observable
@MainActor
final class CorporationAssetsSheet {
    /// ESI's cache time for the route.
    private static let ttl: TimeInterval = 3600

    /// The viewer.
    let characterID: Int64
    let boundCorporationID: Int64
    /// Whether the account was granted `esi-assets.read_corporation_assets.v1`.
    let hasScope: Bool
    private(set) var snapshot: ESISnapshot<ESIAssets>

    var corporationID: Int64? { boundCorporationID }

    /// Progress of the fetch in flight; meaningful only while `state` is `.loading`.
    var progress: AssetsLoadProgress? { context.progress }

    var value: ESIAssets? { snapshot.value }
    var fetchedAt: Date? { snapshot.fetchedAt }
    var state: ESISnapshot<ESIAssets>.State { snapshot.state }
    var revision: Int { snapshot.revision }

    var access: BusinessAccess { .corporation(hasScope: hasScope, isForbidden: snapshot.state.isForbidden) }

    @ObservationIgnored private let context: AssetsFetch.Context
    @ObservationIgnored private let client: Client

    init(characterID: Int64, corporationID: Int64, client: Client, hasScope: Bool) {
        self.characterID = characterID
        self.boundCorporationID = corporationID
        self.hasScope = hasScope
        self.client = client
        let context = AssetsFetch.Context()
        self.context = context
        let routes = AssetsRoutes(
            page: { number in
                let answer = try await client.corporationAssets(corporationID: corporationID, page: number)
                return (answer.records.map(AssetRecord.init), answer.pages, answer.lastModified)
            },
            names: { itemIDs in
                try await client.corporationAssetNames(corporationID: corporationID, itemIDs: itemIDs)
                    .map { ($0.itemId, $0.name) }
            }
        )
        snapshot = ESISnapshot(kind: "corp-\(corporationID)-assets",
                               characterID: characterID,
                               ttl: Self.ttl,
                               cache: ESICache()) {
            try await AssetsFetch.fetch(routes: routes, client: client, context: context)
        }
        context.seed(from: snapshot.value)
    }

    /// Cancels the fetch in flight and stops all disk writes; called by `AccountStore`.
    func invalidate() {
        snapshot.invalidate()
    }

    /// Resolves through ESI the names of types missing from the SDE and amends the value with
    /// them. Best effort, each id requested once per sheet. Returns whether any name was added.
    func resolveTypeNames(missing: Set<Int64>) async -> Bool {
        await context.resolveTypeNames(missing: missing, in: snapshot, client: client)
    }

    /// Refreshes the assets if missing or past the TTL.
    func ensureFresh() async {
        guard hasScope else { return }
        await snapshot.ensureFresh()
    }

    func refresh() async {
        guard hasScope else { return }
        await snapshot.refresh()
    }
}

extension CorporationAssetsSheet: AssetsSource, CorporationBound {}

nonisolated extension AssetRecord {
    init(_ payload: Components.Schemas.CorporationsCorporationIdAssetsGetPayload) {
        self.init(itemID: payload.itemId,
                  typeID: payload.typeId,
                  locationID: payload.locationId,
                  locationFlag: payload.locationFlag.rawValue,
                  locationType: payload.locationType.rawValue,
                  quantity: payload.quantity,
                  isSingleton: payload.isSingleton,
                  isBlueprintCopy: payload.isBlueprintCopy ?? false)
    }
}
