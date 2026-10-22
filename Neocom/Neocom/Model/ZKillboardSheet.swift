import ESIKit
import Foundation
import KillmailKit
import MailKit
import Observation
import ZKillKit

/// zKillboard killmail search by player-defined criteria, app-wide and available without a
/// signed-in character.
///
/// The only owner of zKillboard calls. Uses other owners' routes: `/killmails/{id}/{hash}`
/// through `KillmailsSheet.publicBodies(of:)`, `/characters/{id}/search` through
/// `MailSheet.searchEntities(_:kind:)`, and `/universe/names` through `LookupMemory`.
///
/// Results of the current search are held in memory only.
@Observable
@MainActor
final class ZKillboardSheet {
    /// Why a request to zKillboard failed.
    enum Failure: Error {
        /// zKillboard answered `429`.
        case busy
        /// No killmail with the requested id.
        case notFound
        case failed(any Error)
    }

    enum Phase {
        case idle
        /// Page 1 of `criteria` is being fetched.
        case searching
        /// Page 1, or its first rows, arrived (`pendingBodies` counts the rest); `entries` may
        /// be empty.
        case loaded
        /// Page 1 failed.
        case failed(Failure)
    }

    private(set) var criteria: KillboardCriteria?
    private(set) var phase: Phase = .idle
    /// All pages loaded so far, newest first.
    private(set) var results = KillboardResults()
    private(set) var isLoadingOlder = false
    /// The last `loadOlder()` failure; cleared by the next attempt.
    private(set) var olderFailure: Failure?
    /// Rows of the page being loaded whose bodies are still being fetched from ESI.
    private(set) var pendingBodies = 0
    /// Names resolved for the current search; cleared by every search and `reset()`.
    private(set) var names: [Int64: ESIEntityName] = [:]

    @ObservationIgnored private let zkillboard: ZKillboard
    @ObservationIgnored private let publicClient: Client
    @ObservationIgnored private var memory = LookupMemory()
    /// Incremented by every `search(_:)` and `reset()`; answers for older generations are dropped.
    @ObservationIgnored private var generation = 0
    /// The `reports(signedIn:)` sheet with no character signed in.
    @ObservationIgnored private var signedOutReports: KillmailsSheet?

    init(zkillboard: ZKillboard = ZKillboard(userAgent: ZKillboardSheet.userAgent),
         publicClient: Client = ESIService.publicClient) {
        self.zkillboard = zkillboard
        self.publicClient = publicClient
    }

    /// zKillboard requires a descriptive User-Agent with contact information.
    nonisolated static var userAgent: String { ESIService.userAgent }

    // MARK: - Results

    var entries: [KillboardEntry] { results.entries }

    /// The rows by UTC day, newest first.
    var days: [KillboardDay] { KillboardDay.grouped(results.entries) }

    var isEmpty: Bool {
        if case .loaded = phase { return results.entries.isEmpty }
        return false
    }

    /// Whether an older page is available.
    var hasOlder: Bool {
        guard case .loaded = phase, pendingBodies == 0 || isLoadingOlder else { return false }
        return results.nextPage != nil
    }

    /// A name resolved so far for a character, corporation, alliance or faction.
    func name(of id: Int64?) -> String? {
        guard let id else { return nil }
        return names[id]?.name
    }

    // MARK: - Searching

    /// Starts a new search with page 1 of `criteria`, replacing the previous results. No-op
    /// without a subject.
    ///
    /// Rows appear incrementally: full killmails first, the rest as ESI bodies arrive in
    /// batches; names are resolved afterwards.
    func search(_ criteria: KillboardCriteria) async {
        guard let parameters = criteria.parameters(page: 1) else { return }
        generation += 1
        let generation = generation
        self.criteria = criteria
        results = KillboardResults()
        names = [:]
        olderFailure = nil
        isLoadingOlder = false
        phase = .searching
        do {
            let page = try await zkillboard.killmails(ZKillQuery(parameters))
            guard generation == self.generation else { return }
            try await absorb(page, number: 1, generation: generation)
            guard generation == self.generation else { return }
            phase = .loaded
        } catch {
            guard generation == self.generation else { return }
            if results.entries.isEmpty {
                phase = .failed(Self.failure(error))
            } else {
                phase = .loaded
            }
        }
    }

    /// Appends the next older page; no-op when there is none, one is loading, or page 1 has
    /// not arrived.
    func loadOlder() async {
        guard case .loaded = phase, !isLoadingOlder, pendingBodies == 0, let number = results.nextPage,
              let parameters = criteria?.parameters(page: number) else { return }
        let generation = generation
        isLoadingOlder = true
        olderFailure = nil
        defer { if generation == self.generation { isLoadingOlder = false } }
        do {
            let page = try await zkillboard.killmails(ZKillQuery(parameters))
            guard generation == self.generation else { return }
            try await absorb(page, number: number, generation: generation)
        } catch {
            guard generation == self.generation else { return }
            olderFailure = Self.failure(error)
        }
    }

    func reset() {
        generation += 1
        criteria = nil
        results = KillboardResults()
        names = [:]
        olderFailure = nil
        isLoadingOlder = false
        phase = .idle
    }

    /// The ref (id and hash) of a killmail looked up by id. Does not affect the current search.
    func killmail(id: Int64) async throws(Failure) -> KillmailRef {
        do {
            guard let found = try await zkillboard.killmails(.killmail(id: Int(id))).first else { throw Failure.notFound }
            return KillmailRef(id: Int64(found.killmailID), hash: found.zkb.hash)
        } catch let error as Failure {
            throw error
        } catch {
            throw Self.failure(error)
        }
    }

    /// Drops resolved names, the signed-out reports sheet and the in-memory killmail bodies;
    /// called by `CachedData.clear`. The current search results are kept.
    func dropCachedData() {
        memory = LookupMemory()
        signedOutReports?.invalidate()
        signedOutReports = nil
        Task { await KillmailsSheet.forgetPublicBodies() }
    }

    // MARK: - Reports

    /// The sheet that opens reports: `signedIn`, or a lazily created
    /// `KillmailsSheet.signedOut()`.
    func reports(signedIn: KillmailsSheet?) -> KillmailsSheet {
        if let signedIn { return signedIn }
        if let signedOutReports { return signedOutReports }
        let sheet = KillmailsSheet.signedOut()
        signedOutReports = sheet
        return sheet
    }

    // MARK: - Subject picker

    /// Characters, corporations or alliances matching `text`, via ESI search as the signed-in
    /// character. Empty for other kinds (they come from the SDE), without `mail`, without the
    /// search scope, or for fewer than three characters.
    func subjects(matching text: String, kind: KillboardSubjectKind, mail: MailSheet?) async -> [KillboardSubject] {
        let wanted: MailRecipientKind
        switch kind {
        case .character: wanted = .character
        case .corporation: wanted = .corporation
        case .alliance: wanted = .alliance
        default: return []
        }
        guard let mail else { return [] }
        return await mail.searchEntities(text, kind: wanted)
            .map { KillboardSubject(kind: kind, id: $0.recipient.id, name: $0.name) }
    }

    // MARK: - Fetching

    /// Bodies requested from ESI per batch, so the first rows appear before the whole page.
    private static let bodyBatch = 32

    /// Adds one zKillboard page to `results`: full killmails at once, the rest as ESI bodies
    /// arrive in batches. Paging counts every listed killmail, including ones without a body.
    /// Throws when no killmail of a non-empty page gets a body; stops when a newer search
    /// starts.
    private func absorb(_ page: [ZKillmail], number: Int, generation: Int) async throws {
        var carried: [KillboardEntry] = []
        var missing: [(ref: KillmailRef, zkb: ZKillboardInfo)] = []
        for zkill in page {
            if let killmail = Killmail(zkill) {
                carried.append(KillboardEntry(killmail, zkb: zkill.zkb))
            } else {
                missing.append((KillmailRef(id: Int64(zkill.killmailID), hash: zkill.zkb.hash), zkill.zkb))
            }
        }
        pendingBodies = missing.count
        defer { if generation == self.generation { pendingBodies = 0 } }
        show(carried, number: number, listed: page.count, generation: generation)

        var firstError: (any Error)?
        var shown = carried.count
        var start = 0
        while start < missing.count {
            let batch = missing[start..<min(start + Self.bodyBatch, missing.count)]
            start += batch.count
            do {
                let bodies = try await KillmailsSheet.publicBodies(of: batch.map(\.ref))
                guard generation == self.generation else { return }
                let entries = batch.compactMap { item in bodies[item.ref.id].map { KillboardEntry($0, zkb: item.zkb) } }
                shown += entries.count
                show(entries, number: number, listed: page.count, generation: generation)
            } catch {
                guard generation == self.generation else { return }
                firstError = firstError ?? error
            }
            pendingBodies = missing.count - start
        }
        if shown == 0, let firstError { throw firstError }
    }

    /// Appends rows to `results` and resolves their names in the background.
    private func show(_ entries: [KillboardEntry], number: Int, listed: Int, generation: Int) {
        guard generation == self.generation else { return }
        results = results.appending(entries, number: number, listed: listed)
        if case .searching = phase, !results.entries.isEmpty { phase = .loaded }
        let ids = Set(entries.flatMap(\.killmail.listNameableIDs))
        guard !ids.isEmpty else { return }
        Task { [memory, publicClient] in
            let found = await LookupMemory.names(ids, memory: memory, client: publicClient)
            guard generation == self.generation else { return }
            self.names.merge(found) { _, new in new }
        }
    }

    private static func failure(_ error: any Error) -> Failure {
        if let failure = error as? Failure { return failure }
        if let error = error as? ZKillError {
            switch error {
            case let .http(status, _) where status == 429:
                return .busy
            // ZKillKit maps a non-2xx `{"error": …}` body to `.api` without the status, so a
            // `429` is recognized by its message.
            case let .api(message) where Self.isRateLimited(message):
                return .busy
            case .notFound:
                return .notFound
            default:
                break
            }
        }
        return .failed(error)
    }

    private nonisolated static func isRateLimited(_ message: String) -> Bool {
        let text = message.lowercased()
        return ["429", "rate limit", "ratelimit", "too many", "slow down", "throttl"].contains { text.contains($0) }
    }
}

// MARK: - KillmailKit → ZKillKit

nonisolated extension ZKillQuery {
    init(_ parameters: KillboardQueryParameters) {
        let id = Int(parameters.subjectID)
        let entity: ZKillEntity = switch parameters.subject {
        case .character: .character(id)
        case .corporation: .corporation(id)
        case .alliance: .alliance(id)
        case .faction: .faction(id)
        case .shipType: .shipType(id)
        case .shipGroup: .group(id)
        case .solarSystem: .solarSystem(id)
        case .constellation: .constellation(id)
        case .region: .region(id)
        }
        let side: ZKillSide? = switch parameters.side {
        case .all: nil
        case .kills: .kills
        case .losses: .losses
        }
        let space: ZKillSpace? = parameters.space.map {
            switch $0 {
            case .highsec: .highsec
            case .lowsec: .lowsec
            case .nullsec: .nullsec
            case .wormhole: .wSpace
            case .abyssal: .abyssal
            }
        }
        let engagement: ZKillEngagement? = parameters.engagement.map {
            switch $0 {
            case .solo: .solo
            case .ganked: .ganked
            }
        }
        let period: ZKillPeriod? = if let seconds = parameters.pastSeconds {
            .past(seconds: seconds)
        } else if let month = parameters.month {
            .month(year: month.year, month: month.month)
        } else {
            nil
        }
        self.init(entities: [entity], side: side, space: space, engagement: engagement,
                  awox: parameters.awox, npc: parameters.npc, finalBlowOnly: parameters.finalBlowOnly,
                  minimumISKValue: parameters.minimumValue.map { Int($0) }, period: period,
                  // zKillboard's first page is the bare query.
                  page: parameters.page > 1 ? parameters.page : nil)
    }
}

// MARK: - ZKillKit → KillmailKit

nonisolated extension Killmail {
    /// The killmail as carried by zKillboard, or `nil` without its ESI part. Moon and war are
    /// not included.
    init?(_ zkill: ZKillmail) {
        guard let time = zkill.time, let systemID = zkill.solarSystemID, let victim = zkill.victim,
              let attackers = zkill.attackers else { return nil }
        self.init(id: Int64(zkill.killmailID),
                  hash: zkill.zkb.hash,
                  time: time,
                  solarSystemID: Int64(systemID),
                  victim: KillmailVictim(characterID: victim.characterID.map(Int64.init),
                                         corporationID: victim.corporationID.map(Int64.init),
                                         allianceID: victim.allianceID.map(Int64.init),
                                         factionID: victim.factionID.map(Int64.init),
                                         shipTypeID: Int64(victim.shipTypeID),
                                         damageTaken: Int64(victim.damageTaken),
                                         items: (victim.items ?? []).map(KillmailItem.init)),
                  attackers: attackers.map { attacker in
                      KillmailAttacker(characterID: attacker.characterID.map(Int64.init),
                                       corporationID: attacker.corporationID.map(Int64.init),
                                       allianceID: attacker.allianceID.map(Int64.init),
                                       factionID: attacker.factionID.map(Int64.init),
                                       shipTypeID: attacker.shipTypeID.map(Int64.init),
                                       weaponTypeID: attacker.weaponTypeID.map(Int64.init),
                                       damageDone: Int64(attacker.damageDone),
                                       isFinalBlow: attacker.finalBlow,
                                       securityStatus: attacker.securityStatus ?? 0)
                  })
    }
}

nonisolated extension KillmailItem {
    init(_ item: ZKillItem) {
        self.init(typeID: Int64(item.itemTypeID), flag: Int64(item.flag),
                  destroyed: Int64(item.quantityDestroyed ?? 0), dropped: Int64(item.quantityDropped ?? 0),
                  singleton: Int64(item.singleton), items: (item.items ?? []).map(KillmailItem.init))
    }
}

nonisolated extension KillboardEntry {
    init(_ killmail: Killmail, zkb: ZKillboardInfo) {
        self.init(killmail: killmail, totalValue: zkb.totalValue, points: zkb.points,
                  isSolo: zkb.solo ?? false, isNPC: zkb.npc ?? false, isAwox: zkb.awox ?? false)
    }
}
