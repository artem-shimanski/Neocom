import Foundation
import Observation

/// The market region used for prices, recently picked regions, and the trade hubs (built-in and
/// player-added). A per-device setting stored in `UserDefaults`.
@Observable
@MainActor
final class MarketRegionPreference {
    /// A trade hub: its region and solar system.
    nonisolated struct TradeHub: Sendable, Hashable, Identifiable {
        var regionID: Int64
        var solarSystemID: Int64
        /// The system, since a region can have more than one hub.
        var id: Int64 { solarSystemID }
    }

    /// The Forge, Jita's region.
    nonisolated static let defaultRegionID: Int64 = 10_000_002

    /// The five empire hubs, in display order.
    nonisolated static let tradeHubs: [TradeHub] = [
        TradeHub(regionID: 10_000_002, solarSystemID: 30_000_142),  // The Forge · Jita
        TradeHub(regionID: 10_000_043, solarSystemID: 30_002_187),  // Domain · Amarr
        TradeHub(regionID: 10_000_032, solarSystemID: 30_002_659),  // Sinq Laison · Dodixie
        TradeHub(regionID: 10_000_030, solarSystemID: 30_002_510),  // Heimatar · Rens
        TradeHub(regionID: 10_000_042, solarSystemID: 30_002_053),  // Metropolis · Hek
    ]

    nonisolated static let recentLimit = 5

    /// The region all prices in the app are for.
    private(set) var regionID: Int64
    /// Recently picked regions, most recent first, including the current one.
    private(set) var recentRegionIDs: [Int64]
    /// Player-added hub solar systems, in insertion order; never one of `tradeHubs`.
    private(set) var userHubSystemIDs: [Int64]
    /// The hub `regionID` was picked through; `nil` if the region was picked directly.
    private(set) var selectedHubSystemID: Int64?

    @ObservationIgnored private let defaults: UserDefaults
    private static let regionKey = "market.regionID"
    private static let recentKey = "market.recentRegionIDs"
    private static let userHubsKey = "market.userHubSystemIDs"
    private static let selectedHubKey = "market.hubSystemID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.regionKey) as? NSNumber
        regionID = stored?.int64Value ?? Self.defaultRegionID
        recentRegionIDs = (defaults.array(forKey: Self.recentKey) as? [NSNumber])?.map(\.int64Value) ?? []
        userHubSystemIDs = (defaults.array(forKey: Self.userHubsKey) as? [NSNumber])?.map(\.int64Value) ?? []
        selectedHubSystemID = (defaults.object(forKey: Self.selectedHubKey) as? NSNumber)?.int64Value
    }

    /// Makes `regionID` the market region and moves it to the front of the recent list.
    func select(_ regionID: Int64, hubSystemID: Int64? = nil) {
        self.regionID = regionID
        selectedHubSystemID = hubSystemID
        var recent = recentRegionIDs.filter { $0 != regionID }
        recent.insert(regionID, at: 0)
        recentRegionIDs = Array(recent.prefix(Self.recentLimit))
        defaults.set(NSNumber(value: regionID), forKey: Self.regionKey)
        defaults.set(recentRegionIDs.map { NSNumber(value: $0) }, forKey: Self.recentKey)
        defaults.set(hubSystemID.map { NSNumber(value: $0) }, forKey: Self.selectedHubKey)
    }

    /// The hub to show for `regionID`: the one the current region was picked through, else the
    /// region's built-in hub.
    func hubSystemID(forRegion regionID: Int64) -> Int64? {
        if regionID == self.regionID, let selectedHubSystemID { return selectedHubSystemID }
        return Self.tradeHubs.first { $0.regionID == regionID }?.solarSystemID
    }

    // MARK: - User hubs

    /// Whether `solarSystemID` is a built-in or player-added hub.
    func isHub(_ solarSystemID: Int64) -> Bool {
        Self.tradeHubs.contains { $0.solarSystemID == solarSystemID } || userHubSystemIDs.contains(solarSystemID)
    }

    /// Appends a system to the player's hubs; no-op if it is already a hub.
    func addUserHub(_ solarSystemID: Int64) {
        guard !isHub(solarSystemID) else { return }
        userHubSystemIDs.append(solarSystemID)
        saveUserHubs()
    }

    func removeUserHubs(_ solarSystemIDs: some Sequence<Int64>) {
        let removed = Set(solarSystemIDs)
        userHubSystemIDs.removeAll { removed.contains($0) }
        // The selected region stays; only its hub is cleared.
        if let selectedHubSystemID, removed.contains(selectedHubSystemID) {
            self.selectedHubSystemID = nil
            defaults.removeObject(forKey: Self.selectedHubKey)
        }
        saveUserHubs()
    }

    private func saveUserHubs() {
        defaults.set(userHubSystemIDs.map { NSNumber(value: $0) }, forKey: Self.userHubsKey)
    }
}
