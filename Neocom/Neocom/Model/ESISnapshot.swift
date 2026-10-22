import Foundation
import Observation

/// An ESI value mirrored on disk and refreshed on demand.
///
/// Loads the cached value synchronously in `init`, applies one TTL to the whole value,
/// coalesces concurrent refreshes into one request, and never clears the value on a failed
/// fetch.
@Observable
@MainActor
final class ESISnapshot<Value: Codable & Sendable> {
    enum State {
        case idle
        case loading
        case failed(any Error)
    }

    private(set) var value: Value?
    private(set) var fetchedAt: Date?
    private(set) var state: State = .idle
    /// Incremented on every value change; usable as a memoization key.
    private(set) var revision: Int = 0

    @ObservationIgnored private let kind: String
    @ObservationIgnored private let owner: ESICache.Owner
    /// When a value fetched at the given instant stops being fresh.
    @ObservationIgnored private let freshUntil: @Sendable (Date) -> Date
    @ObservationIgnored private let cache: ESICache
    @ObservationIgnored private let fetch: @Sendable () async throws -> Value

    /// The in-flight refresh, awaited by all concurrent callers.
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// Counts `replace(_:)` calls, so an in-flight fetch can detect that its answer is older.
    @ObservationIgnored private var replacements = 0

    /// Set by `invalidate()`; no disk writes happen afterwards.
    @ObservationIgnored private var isInvalidated = false

    /// Called with every new value (fetch, `replace(_:)`, `amend(_:)`) after it is stored.
    @ObservationIgnored var didUpdate: ((Value) -> Void)?

    /// A character's value with a fixed TTL.
    convenience init(kind: String,
                     characterID: Int64,
                     ttl: TimeInterval,
                     cache: ESICache,
                     fetch: @escaping @Sendable () async throws -> Value) {
        self.init(kind: kind, owner: .character(characterID), ttl: ttl, cache: cache, fetch: fetch)
    }

    /// Any owner, with a fixed TTL.
    convenience init(kind: String,
                     owner: ESICache.Owner,
                     ttl: TimeInterval,
                     cache: ESICache,
                     fetch: @escaping @Sendable () async throws -> Value) {
        self.init(kind: kind, owner: owner, cache: cache,
                  freshUntil: { $0.addingTimeInterval(ttl) }, fetch: fetch)
    }

    /// Any owner, with freshness computed by `freshUntil` from the fetch time.
    init(kind: String,
         owner: ESICache.Owner,
         cache: ESICache,
         freshUntil: @escaping @Sendable (Date) -> Date,
         fetch: @escaping @Sendable () async throws -> Value) {
        self.kind = kind
        self.owner = owner
        self.freshUntil = freshUntil
        self.cache = cache
        self.fetch = fetch

        // Synchronous, so the first frame shows the cached value.
        if let entry = cache.load(Value.self, kind: kind, owner: owner) {
            value = entry.value
            fetchedAt = entry.fetchedAt
        }
    }

    /// Whether the value exists and is not past its freshness.
    var isFresh: Bool {
        guard let fetchedAt else { return false }
        return Date.now < freshUntil(fetchedAt)
    }

    /// Refreshes the value if missing or past the TTL.
    func ensureFresh() async {
        if isFresh {
            return
        }
        await load()
    }

    /// Loads regardless of the TTL, joining a load already in flight.
    func refresh() async {
        await load()
    }

    /// Starts a fetch, or awaits the one in flight.
    private func load() async {
        guard !isInvalidated else { return }
        if let loading {
            await loading.value
            return
        }

        state = .loading

        let task = Task { [weak self] in
            guard let self else { return }
            await self.perform()
        }
        loading = task
        await task.value
        loading = nil
    }

    /// Replaces the value with one known to be newer than any fetch would return, e.g. after a
    /// POST or DELETE whose GET route ESI still serves from cache. Writes the cache and restarts
    /// the TTL; a fetch in flight is discarded.
    func replace(_ newValue: Value) {
        guard !isInvalidated else { return }
        let now = Date.now
        replacements += 1
        value = newValue
        fetchedAt = now
        revision += 1
        state = .idle
        cache.save(.init(value: newValue, fetchedAt: now), kind: kind, owner: owner)
        didUpdate?(newValue)
    }

    /// Updates the value with data derived from the same fetch (e.g. names resolved later).
    /// Keeps `fetchedAt`, and a fetch in flight still publishes its answer. Ignored without a
    /// value.
    func amend(_ newValue: Value) {
        guard !isInvalidated, value != nil else { return }
        value = newValue
        revision += 1
        cache.save(.init(value: newValue, fetchedAt: fetchedAt ?? .now), kind: kind, owner: owner)
        didUpdate?(newValue)
    }

    /// Cancels the fetch in flight and stops all further cache writes. The in-memory value is
    /// kept.
    func invalidate() {
        isInvalidated = true
        loading?.cancel()
    }

    private func perform() async {
        let replacementsAtStart = replacements
        do {
            let newValue = try await fetch()
            guard !isInvalidated else {
                state = .idle
                return
            }
            // A `replace(_:)` during the request makes this answer stale; `replace(_:)` has
            // already reset `state`.
            guard replacements == replacementsAtStart else { return }

            let now = Date.now
            value = newValue
            fetchedAt = now
            revision += 1
            state = .idle
            cache.save(.init(value: newValue, fetchedAt: now), kind: kind, owner: owner)
            didUpdate?(newValue)
        } catch {
            // A failed fetch keeps `value`; the error is reported through `state`.
            state = isInvalidated ? .idle : .failed(error)
        }
    }
}

extension ESISnapshot.State {
    /// The last fetch failed with ESI's `403`.
    var isForbidden: Bool {
        if case let .failed(error) = self { return error.isESIForbidden }
        return false
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var error: (any Error)? {
        if case let .failed(error) = self { return error }
        return nil
    }
}
