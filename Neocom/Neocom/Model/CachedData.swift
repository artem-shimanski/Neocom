import Foundation

/// Data fetched from EVE servers: the `ESICache` files and the images in `URLCache.shared`.
/// Player-created data (keychain accounts, SwiftData, `UserDefaults`) is not included.
enum CachedData {
    nonisolated struct Usage: Sendable, Hashable {
        var bytes: Int64
        /// No ESI files, and the image cache holds only its own index.
        var isEmpty: Bool
    }

    /// Size of `URLCache`'s index database, which remains after its responses are removed.
    nonisolated private static let imageCacheFloor = 128 * 1024

    /// Measures the cache directories off the main actor.
    static func usage() async -> Usage {
        await Task.detached(priority: .utility) {
            let files = ESICache.diskUsage()
            let images = URLCache.shared.currentDiskUsage
            return Usage(bytes: files.bytes + Int64(images),
                         isEmpty: files.files == 0 && images < imageCacheFloor)
        }.value
    }

    /// Clears all cached data. In-memory snapshots are dropped first so in-flight fetches do not
    /// write their files back; everything happens in one main-actor turn, so refetches start only
    /// after the files are gone.
    static func clear(accounts: AccountStore, market: MarketSheet, zkillboard: ZKillboardSheet,
                      serverStatus: ServerStatusSheet) {
        accounts.dropCachedData()
        market.dropCachedData()
        zkillboard.dropCachedData()
        serverStatus.dropCachedData()
        ESICache.removeEverything()
        URLCache.shared.removeAllCachedResponses()
    }
}
