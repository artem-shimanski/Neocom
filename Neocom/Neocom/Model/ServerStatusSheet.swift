import ESIKit
import Foundation
import Observation

/// Tranquility server status, app-wide and available without a signed-in character.
///
/// The only owner of `/status`. Cached on disk under `ESICache.Owner.universe`.
@Observable
@MainActor
final class ServerStatusSheet {
    /// ESI caches `/status` for 30 seconds.
    static let ttl: TimeInterval = 60

    private(set) var status: ESISnapshot<ServerStatus>

    @ObservationIgnored private let client: Client
    @ObservationIgnored private let cache: ESICache

    // `cache` defaults to `nil` so the default instance is created on the main actor.
    init(client: Client = ESIService.publicClient, cache: ESICache? = nil) {
        let cache = cache ?? ESICache()
        self.client = client
        self.cache = cache
        status = Self.makeStatus(client: client, cache: cache)
    }

    private static func makeStatus(client: Client, cache: ESICache) -> ESISnapshot<ServerStatus> {
        ESISnapshot(kind: "server-status", owner: .universe, ttl: Self.ttl, cache: cache) {
            let status = try await client.serverStatus()
            return ServerStatus(players: status.players,
                                vip: status.vip ?? false,
                                serverVersion: status.serverVersion,
                                startTime: status.startTime)
        }
    }

    /// The state at `now`, or `nil` before anything is known.
    func state(now: Date) -> ServerState? {
        ServerState.classify(status: status.value, failure: status.state.error, now: now)
    }

    func ensureFresh() async {
        await status.ensureFresh()
    }

    /// Refreshes the status every `ttl` until the calling task is cancelled, failures included.
    func keepFresh() async {
        while !Task.isCancelled {
            await status.ensureFresh()
            try? await Task.sleep(for: .seconds(Self.ttl))
        }
    }

    /// Drops the in-memory snapshot; called by `CachedData.clear`.
    func dropCachedData() {
        status.invalidate()
        status = Self.makeStatus(client: client, cache: cache)
    }
}
