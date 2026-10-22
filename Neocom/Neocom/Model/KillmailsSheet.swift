import ESIKit
import Foundation
import KillmailKit
import Observation

/// The character's recent killmails loaded so far, as stored in `ESICache`: paging, bodies, and
/// the names shown in list rows.
nonisolated struct ESIKillmailList: Codable, Sendable, Hashable {
    var list: KillmailRecentList
    /// Bodies by id. A ref whose body has not been fetched yet is omitted from `loaded`.
    var killmails: [Int64: Killmail]
    var names: [Int64: ESIEntityName]

    /// The killmails with a body, newest first.
    var loaded: [Killmail] { list.refs.compactMap { killmails[$0.id] } }
}

/// A killmail with its victim and attackers named.
nonisolated struct ESIKillmail: Codable, Sendable, Hashable {
    var killmail: Killmail
    var names: [Int64: ESIEntityName]
}

/// A character's kills and losses.
///
/// The only owner of `/characters/{id}/killmails/recent` and `/killmails/{id}/{hash}`;
/// `ZKillboardSheet` reaches the latter through `publicBodies(of:)`. A killmail body never
/// changes, so a fetched body is reused and never requested again.
@Observable
@MainActor
final class KillmailsSheet {
    /// ESI caches the recent list for five minutes.
    private static let recentTTL: TimeInterval = 300
    /// A killmail never changes; only the names on it may.
    private static let killmailTTL: TimeInterval = 30 * 86_400
    /// Per-report files older than this are deleted on init.
    private static let killmailRetention: TimeInterval = 90 * 86_400
    private static let killmailPrefix = "killmail-"

    let characterID: Int64
    /// Whether the account was granted `esi-killmails.read_killmails.v1`.
    let hasScope: Bool

    /// The recent list with every body fetched so far.
    let recent: ESISnapshot<ESIKillmailList>
    private(set) var isLoadingOlder = false

    @ObservationIgnored private let client: Client
    /// `/killmails/{id}/{hash}` is public and requested without the character's token.
    @ObservationIgnored private let publicClient: Client
    @ObservationIgnored private let memory: LookupMemory
    @ObservationIgnored private let reference: SheetReference
    @ObservationIgnored private var killmailSnapshots: [Int64: ESISnapshot<ESIKillmail>] = [:]
    @ObservationIgnored private var isInvalidated = false

    init(characterID: Int64, client: Client, publicClient: Client = ESIService.publicClient, scopes: (String) -> Bool) {
        self.characterID = characterID
        self.client = client
        self.publicClient = publicClient
        let hasScope = scopes(SSOConfiguration.Scope.killmails)
        self.hasScope = hasScope
        let memory = LookupMemory()
        self.memory = memory
        let cache = ESICache()
        cache.removeFiles(of: .universe, prefix: Self.killmailPrefix,
                          writtenBefore: Date.now.addingTimeInterval(-Self.killmailRetention))

        let reference = SheetReference()
        self.reference = reference
        recent = ESISnapshot(kind: "killmails-recent", characterID: characterID, ttl: Self.recentTTL, cache: cache) {
            guard hasScope else { throw ESIError.http(status: 403, message: nil) }
            let answer = try await client.recentKillmails(characterID: characterID, page: 1)
            let page = answer.killmails.map { KillmailRef(id: $0.killmailId, hash: $0.killmailHash) }
            // Read after the answer arrives, so a page appended by `loadOlder()` meanwhile is kept.
            let previous = await reference.sheet?.recent.value
            let list = (previous?.list ?? KillmailRecentList()).refreshed(withFirstPage: page, pages: answer.pages)
            let bodies = try await Self.bodies(of: list.refs, known: previous?.killmails ?? [:], client: publicClient)
            let names = await LookupMemory.names(bodies.values.flatMap(\.listNameableIDs), memory: memory, client: client)
            // `loadOlder()` may have appended a page while the bodies were fetched; it is merged
            // back in, since this answer replaces the value.
            guard let latest = await reference.sheet?.recent.value,
                  latest.list.loadedPages > (previous?.list.loadedPages ?? 0) else {
                return ESIKillmailList(list: list, killmails: bodies, names: names)
            }
            let joined = latest.list.refreshed(withFirstPage: page, pages: answer.pages)
            let ids = Set(joined.refs.map(\.id))
            return ESIKillmailList(list: joined,
                                   killmails: latest.killmails.merging(bodies) { _, new in new }.filter { ids.contains($0.key) },
                                   names: latest.names.merging(names) { _, new in new })
        }
        memory.seed(names: recent.value?.names ?? [:])
        reference.sheet = self
    }

    /// A sheet for viewing public killmails with no character signed in. The recent list is
    /// never requested, and character id `0` matches no participant.
    static func signedOut() -> KillmailsSheet {
        KillmailsSheet(characterID: 0, client: ESIService.publicClient, scopes: { _ in false })
    }

    /// The account lacks the scope, or ESI answered `403`.
    var isMissingScope: Bool { !hasScope || recent.state.isForbidden }

    /// The killmails loaded so far, newest first.
    var killmails: [Killmail] { recent.value?.loaded ?? [] }

    /// Kill and loss counts without values; `nil` until the list is loaded.
    var counts: KillmailListStats? {
        recent.value.map { KillmailListStats($0.loaded, pilotID: characterID) }
    }

    /// The list's totals, including values at `price`.
    func stats(price: (Int64) -> Double?) -> KillmailListStats {
        KillmailListStats(killmails, pilotID: characterID, price: price)
    }

    func side(of killmail: Killmail) -> KillmailSide {
        killmail.side(for: characterID)
    }

    /// Whether an older page is available.
    var hasOlder: Bool { recent.value?.list.hasMore ?? false }

    /// A name resolved so far for a character, corporation, alliance or faction.
    func name(of id: Int64?) -> String? {
        guard let id else { return nil }
        return recent.value?.names[id]?.name ?? memory.names[id]?.name
    }

    /// Refreshes the list if missing or past its TTL.
    func ensureFresh() async {
        guard hasScope else { return }
        await recent.ensureFresh()
    }

    /// Refetches page 1; older pages already loaded are kept.
    func refresh() async {
        guard hasScope else { return }
        await recent.refresh()
    }

    /// Appends the next older page; no-op when there is none or one is loading. Does not change
    /// the list's `fetchedAt`.
    func loadOlder() async throws {
        guard hasScope, !isLoadingOlder, let number = recent.value?.list.nextPage else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        let refs: [KillmailRef]
        let pages: Int
        do {
            let answer = try await client.recentKillmails(characterID: characterID, page: number)
            refs = answer.killmails.map { KillmailRef(id: $0.killmailId, hash: $0.killmailHash) }
            pages = answer.pages
        } catch let ESIError.http(status, _) where status == 404 {
            // The list shrank since page 1 was fetched.
            refs = []
            pages = number - 1
        }
        guard let before = recent.value else { return }
        let list = before.list.appending(page: refs, number: number, pages: pages)
        let bodies = try await Self.bodies(of: list.refs, known: before.killmails, client: publicClient)
        let names = await LookupMemory.names(bodies.values.flatMap(\.listNameableIDs), memory: memory, client: client)
        guard !isInvalidated, let current = recent.value else { return }
        // A refresh may have completed meanwhile; its page 1 and bodies are kept.
        let merged = current.list.appending(page: refs, number: number, pages: pages)
        recent.amend(ESIKillmailList(list: merged,
                                     killmails: current.killmails.merging(bodies) { current, _ in current },
                                     names: current.names.merging(names) { _, new in new }))
    }

    // MARK: - Single killmail

    /// Any killmail with all participants named; the same snapshot for the same killmail on
    /// every call. Cached under `.universe`, since the route is public.
    func killmail(_ ref: KillmailRef) -> ESISnapshot<ESIKillmail> {
        if let snapshot = killmailSnapshots[ref.id] { return snapshot }
        let client = client
        let publicClient = publicClient
        let memory = memory
        let reference = reference
        let snapshot = ESISnapshot<ESIKillmail>(kind: "\(Self.killmailPrefix)\(ref.id)", owner: .universe,
                                                ttl: Self.killmailTTL, cache: ESICache()) {
            // Reuses a body from the recent list or from `KillmailBodyMemory`.
            var known = await reference.sheet?.recent.value?.killmails[ref.id]
            if known == nil { known = await KillmailBodyMemory.shared.body(of: ref.id) }
            let killmail = if let known { known } else { try await Self.publicBody(ref, client: publicClient) }
            let names = await LookupMemory.names(killmail.nameableIDs, memory: memory, client: client)
            return ESIKillmail(killmail: killmail, names: names)
        }
        memory.seed(names: snapshot.value?.names ?? [:])
        killmailSnapshots[ref.id] = snapshot
        return snapshot
    }

    func killmail(id: Int64, hash: String) -> ESISnapshot<ESIKillmail> {
        killmail(KillmailRef(id: id, hash: hash))
    }

    /// Stops all disk writes; called by `AccountStore` when it drops the sheet.
    func invalidate() {
        isInvalidated = true
        recent.invalidate()
        killmailSnapshots.values.forEach { $0.invalidate() }
    }

    // MARK: - Fetching

    /// The only call site of `/killmails/{id}/{hash}`.
    nonisolated private static func fetch(_ ref: KillmailRef, client: Client) async throws -> Killmail {
        Killmail(hash: ref.hash, try await client.killmail(id: ref.id, hash: ref.hash))
    }

    /// Fetches one body and stores it in `KillmailBodyMemory`.
    nonisolated private static func publicBody(_ ref: KillmailRef, client: Client) async throws -> Killmail {
        let killmail = try await fetch(ref, client: client)
        await KillmailBodyMemory.shared.remember([killmail])
        return killmail
    }

    /// Concurrency for `publicBodies(of:)`. ESI meters the route in its own per-application
    /// rate-limit group (3600 tokens per 15 minutes, 2 per call), so the width affects only
    /// latency, not the budget.
    nonisolated static let publicWidth = 16

    /// The bodies of `refs` from the public route, without a character; used by
    /// `ZKillboardSheet`. Failed bodies are omitted; the error is rethrown only if all fail.
    /// Results are kept in `KillmailBodyMemory`, not on disk.
    nonisolated static func publicBodies(of refs: [KillmailRef]) async throws -> [Int64: Killmail] {
        let known = await KillmailBodyMemory.shared.bodies(of: refs.map(\.id))
        let bodies = try await bodies(of: refs, known: known, client: ESIService.publicClient, width: publicWidth)
        await KillmailBodyMemory.shared.remember(bodies.filter { known[$0.key] == nil }.map(\.value))
        return bodies
    }

    /// Empties `KillmailBodyMemory`; called by `CachedData.clear`.
    nonisolated static func forgetPublicBodies() async {
        await KillmailBodyMemory.shared.forget()
    }

    /// The bodies of `refs`, reusing `known` and fetching the rest `width` at a time. Failed
    /// bodies are omitted; the error is rethrown only if all requested bodies fail.
    nonisolated private static func bodies(of refs: [KillmailRef], known: [Int64: Killmail],
                                           client: Client, width: Int = ESIParallel.width) async throws -> [Int64: Killmail] {
        let ids = Set(refs.map(\.id))
        var bodies = known.filter { ids.contains($0.key) }
        let missing = refs.filter { bodies[$0.id] == nil }
        guard !missing.isEmpty else { return bodies }
        let answers = try await ESIParallel.boundedMap(missing, width: width) { ref -> Result<Killmail, any Error> in
            do {
                return .success(try await fetch(ref, client: client))
            } catch {
                return .failure(error)
            }
        }
        var firstError: (any Error)?
        for answer in answers {
            switch answer {
            case let .success(killmail): bodies[killmail.id] = killmail
            case let .failure(error): firstError = firstError ?? error
            }
        }
        if let firstError, answers.allSatisfy({ if case .failure = $0 { true } else { false } }) {
            throw firstError
        }
        return bodies
    }
}

/// In-memory cache of killmail bodies fetched without a character, for the app's lifetime.
/// Cleared entirely when it would exceed `capacity`.
private actor KillmailBodyMemory {
    static let shared = KillmailBodyMemory()
    static let capacity = 5000

    private var bodies: [Int64: Killmail] = [:]

    func body(of id: Int64) -> Killmail? { bodies[id] }

    func bodies(of ids: [Int64]) -> [Int64: Killmail] {
        var found: [Int64: Killmail] = [:]
        for id in ids { if let body = bodies[id] { found[id] = body } }
        return found
    }

    func remember(_ killmails: [Killmail]) {
        guard !killmails.isEmpty else { return }
        if bodies.count + killmails.count > Self.capacity { bodies.removeAll(keepingCapacity: true) }
        for killmail in killmails { bodies[killmail.id] = killmail }
    }

    func forget() {
        bodies = [:]
    }
}

/// A weak reference to the sheet for fetch closures created in `init`, before `self` can be
/// captured.
@MainActor
private final class SheetReference {
    weak var sheet: KillmailsSheet?
}

// MARK: - ESI → KillmailKit

nonisolated extension Killmail {
    init(hash: String, _ payload: Components.Schemas.KillmailsKillmailIdKillmailHashGet) {
        let victim = payload.victim
        self.init(id: payload.killmailId,
                  hash: hash,
                  time: payload.killmailTime,
                  solarSystemID: payload.solarSystemId,
                  moonID: payload.moonId,
                  warID: payload.warId,
                  victim: KillmailVictim(characterID: victim.characterId,
                                         corporationID: victim.corporationId,
                                         allianceID: victim.allianceId,
                                         factionID: victim.factionId,
                                         shipTypeID: victim.shipTypeId,
                                         damageTaken: victim.damageTaken,
                                         items: (victim.items ?? []).map { item in
                                             KillmailItem(typeID: item.itemTypeId, flag: item.flag,
                                                          destroyed: item.quantityDestroyed ?? 0,
                                                          dropped: item.quantityDropped ?? 0,
                                                          singleton: item.singleton,
                                                          items: (item.items ?? []).map { inner in
                                                              KillmailItem(typeID: inner.itemTypeId, flag: inner.flag,
                                                                           destroyed: inner.quantityDestroyed ?? 0,
                                                                           dropped: inner.quantityDropped ?? 0,
                                                                           singleton: inner.singleton)
                                                          })
                                         }),
                  attackers: payload.attackers.map { attacker in
                      KillmailAttacker(characterID: attacker.characterId,
                                       corporationID: attacker.corporationId,
                                       allianceID: attacker.allianceId,
                                       factionID: attacker.factionId,
                                       shipTypeID: attacker.shipTypeId,
                                       weaponTypeID: attacker.weaponTypeId,
                                       damageDone: attacker.damageDone,
                                       isFinalBlow: attacker.finalBlow,
                                       securityStatus: attacker.securityStatus)
                  })
    }
}
