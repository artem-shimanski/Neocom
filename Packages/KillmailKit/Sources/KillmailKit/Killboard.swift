// zKillboard search as plain data: criteria, query parameters, result rows, paging, kill or
// loss from the subject's side, and killmail id parsing. Independent of the zKillboard client
// types; `KillboardQueryParameters` maps onto a query one to one.

import Foundation

// MARK: - Subject

/// What a search is about. Names come from the SDE (ships, groups, places, factions) or from
/// ESI's search (characters, corporations, alliances) — never from zKillboard.
public enum KillboardSubjectKind: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case character
    case corporation
    case alliance
    case faction
    case shipType
    case shipGroup
    case solarSystem
    case constellation
    case region

    public var id: Self { self }

    /// A killmail has this subject on one side of it — as the victim, or among the attackers —
    /// so kills and losses, and "final blow only", mean something. A place has no side: every
    /// killmail there is just a killmail there.
    public var hasSide: Bool {
        switch self {
        case .character, .corporation, .alliance, .faction, .shipType, .shipGroup: true
        case .solarSystem, .constellation, .region: false
        }
    }

    /// Found through ESI's search (signed-in character needed), not the SDE.
    public var isSearchedOnESI: Bool {
        switch self {
        case .character, .corporation, .alliance: true
        default: false
        }
    }
}

public struct KillboardSubject: Codable, Sendable, Hashable, Identifiable {
    public var kind: KillboardSubjectKind
    public var id: Int64
    public var name: String

    public init(kind: KillboardSubjectKind, id: Int64, name: String) {
        self.kind = kind
        self.id = id
        self.name = name
    }

    /// Kill or loss from the subject's side, judged by the victim: a loss when the victim is
    /// the subject (its pilot, corporation, alliance or faction; its ship, or a ship of its
    /// group), a kill otherwise. `nil` for a place, which has no side, and for a group subject
    /// whose victim's group is unknown (`groupOf` gave none — the SDE not read yet, or a type
    /// it lacks). `groupOf` names a ship type's group (from the SDE); it is asked only for a
    /// group subject.
    ///
    /// Only right when kills and losses were asked for together: a Vexor killed by a Vexor is
    /// both. A search's rows take `KillboardCriteria.side(of:groupOf:)`, which goes by what
    /// was asked first.
    public func side(of killmail: Killmail, groupOf: (Int64) -> Int64? = { _ in nil }) -> KillmailSide? {
        let victim = killmail.victim
        let isVictim: Bool
        switch kind {
        case .character: isVictim = victim.characterID == id
        case .corporation: isVictim = victim.corporationID == id
        case .alliance: isVictim = victim.allianceID == id
        case .faction: isVictim = victim.factionID == id
        case .shipType: isVictim = victim.shipTypeID == id
        case .shipGroup:
            guard let group = groupOf(victim.shipTypeID) else { return nil }
            isVictim = group == id
        case .solarSystem, .constellation, .region: return nil
        }
        return isVictim ? .loss : .kill
    }
}

// MARK: - Criteria

/// Security class of the system: `nil` in `KillboardCriteria.space` is any.
public enum KillboardSpace: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case highsec
    case lowsec
    case nullsec
    case wormhole
    case abyssal

    public var id: Self { self }
}

/// How many took part: `nil` in `KillboardCriteria.engagement` is any.
public enum KillboardEngagement: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case solo
    case ganked

    public var id: Self { self }
}

/// `NPC` and `AWOX`: any, only those, or none of those.
public enum KillboardInclusion: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case any
    case only
    case excluded

    public var id: Self { self }

    /// zKillboard's `npc/1`, `npc/0`, or nothing.
    public var flag: Bool? {
        switch self {
        case .any: nil
        case .only: true
        case .excluded: false
        }
    }
}

/// When. zKillboard reaches back one week with a past period; a month can be any month.
public enum KillboardPeriod: Codable, Sendable, Hashable {
    case any
    case pastHour
    case pastDay
    case pastWeek
    /// A calendar month, EVE time (UTC).
    case month(year: Int, month: Int)

    /// zKillboard's `pastSeconds`: a whole number of hours, a week at most.
    public var pastSeconds: Int? {
        switch self {
        case .pastHour: 3600
        case .pastDay: 86_400
        case .pastWeek: 604_800
        case .any, .month: nil
        }
    }

    /// The menu's months: the current UTC month and the `count - 1` before it, newest first.
    public static func recentMonths(_ count: Int = 3, now: Date = .now) -> [KillboardPeriod] {
        let calendar = Calendar.utc
        let parts = calendar.dateComponents([.year, .month], from: now)
        guard var year = parts.year, var month = parts.month else { return [] }
        var months: [KillboardPeriod] = []
        for _ in 0..<max(0, count) {
            months.append(.month(year: year, month: month))
            month -= 1
            if month == 0 {
                month = 12
                year -= 1
            }
        }
        return months
    }
}

/// Everything the search form sets. Nothing is asked of zKillboard until Search.
public struct KillboardCriteria: Codable, Sendable, Hashable {
    /// `MIN. VALUE` options: zKillboard takes multiples of 500M only.
    public static let minimumValueOptions: [Int64] = [
        500_000_000, 1_000_000_000, 5_000_000_000, 10_000_000_000, 50_000_000_000, 100_000_000_000,
    ]

    public var subject: KillboardSubject?
    public var side: KillmailFilter
    public var space: KillboardSpace?
    public var engagement: KillboardEngagement?
    public var npc: KillboardInclusion
    public var awox: KillboardInclusion
    public var period: KillboardPeriod
    /// One of `minimumValueOptions`, or `nil` for any.
    public var minimumValue: Int64?
    public var finalBlowOnly: Bool

    public init(subject: KillboardSubject? = nil, side: KillmailFilter = .all, space: KillboardSpace? = nil,
                engagement: KillboardEngagement? = nil, npc: KillboardInclusion = .any, awox: KillboardInclusion = .any,
                period: KillboardPeriod = .any, minimumValue: Int64? = nil, finalBlowOnly: Bool = false) {
        self.subject = subject
        self.side = side
        self.space = space
        self.engagement = engagement
        self.npc = npc
        self.awox = awox
        self.period = period
        self.minimumValue = minimumValue
        self.finalBlowOnly = finalBlowOnly
    }

    /// Kill or loss of a result row from the subject's side. Kills only or losses only: what
    /// was asked — zKillboard answered that side, even where the victim is the subject as
    /// well (a Vexor killed by a Vexor, in a Vexor's kills). Both: judged by the victim
    /// (`KillboardSubject.side(of:groupOf:)`). `nil` without a subject, or for a place.
    public func side(of killmail: Killmail, groupOf: (Int64) -> Int64? = { _ in nil }) -> KillmailSide? {
        guard let subject, subject.kind.hasSide else { return nil }
        switch side {
        case .kills: return .kill
        case .losses: return .loss
        case .all: return subject.side(of: killmail, groupOf: groupOf)
        }
    }

    /// Search is offered once a subject is chosen: zKillboard pages and periods need one.
    public var canSearch: Bool { subject != nil }

    /// The query for page `page` (1...`KillboardResults.maxPage`), or `nil` without a subject.
    /// Side and final blow are dropped for a place (they mean nothing there); a minimum value
    /// that is not a multiple of 500M is rounded down to one, and dropped below 500M.
    public func parameters(page: Int = 1) -> KillboardQueryParameters? {
        guard let subject, subject.id > 0 else { return nil }
        let hasSide = subject.kind.hasSide
        let value = minimumValue.map { $0 / Self.valueStep * Self.valueStep }.flatMap { $0 > 0 ? $0 : nil }
        let pastSeconds = period.pastSeconds
        var month: KillboardQueryParameters.Month?
        if case let .month(year, number) = period { month = .init(year: year, month: number) }
        return KillboardQueryParameters(
            subject: subject.kind,
            subjectID: subject.id,
            side: hasSide ? side : .all,
            space: space,
            engagement: engagement,
            npc: npc.flag,
            awox: awox.flag,
            finalBlowOnly: hasSide && finalBlowOnly,
            minimumValue: value,
            pastSeconds: pastSeconds,
            month: month,
            page: min(max(1, page), KillboardResults.maxPage)
        )
    }

    private static let valueStep: Int64 = 500_000_000
}

/// What `KillboardCriteria` asks zKillboard, in plain values: one segment each.
public struct KillboardQueryParameters: Sendable, Hashable {
    public struct Month: Sendable, Hashable {
        public var year: Int
        public var month: Int

        public init(year: Int, month: Int) {
            self.year = year
            self.month = month
        }
    }

    public var subject: KillboardSubjectKind
    public var subjectID: Int64
    /// `.all` sends no side.
    public var side: KillmailFilter
    public var space: KillboardSpace?
    public var engagement: KillboardEngagement?
    public var npc: Bool?
    public var awox: Bool?
    public var finalBlowOnly: Bool
    public var minimumValue: Int64?
    /// Exclusive with `month`.
    public var pastSeconds: Int?
    public var month: Month?
    public var page: Int
}

// MARK: - Results

/// One result row: the killmail, and what zKillboard adds to it.
public struct KillboardEntry: Codable, Sendable, Hashable, Identifiable {
    public var killmail: Killmail
    /// zKillboard's `totalValue`, its own estimate.
    public var totalValue: Double?
    public var points: Int?
    public var isSolo: Bool
    public var isNPC: Bool
    public var isAwox: Bool

    public init(killmail: Killmail, totalValue: Double? = nil, points: Int? = nil,
                isSolo: Bool = false, isNPC: Bool = false, isAwox: Bool = false) {
        self.killmail = killmail
        self.totalValue = totalValue
        self.points = points
        self.isSolo = isSolo
        self.isNPC = isNPC
        self.isAwox = isAwox
    }

    public var id: Int64 { killmail.id }
    /// `5 INVOLVED`.
    public var involved: Int { killmail.attackers.count }
}

/// The rows loaded so far for one search, newest first, and how far the paging got.
public struct KillboardResults: Sendable, Hashable {
    /// zKillboard's page: a shorter one is the last.
    public static let pageSize = 200
    /// The last page zKillboard serves.
    public static let maxPage = 100

    public private(set) var entries: [KillboardEntry]
    public private(set) var loadedPages: Int
    /// No older page to ask for: one came back short (or empty), or the last was loaded.
    public private(set) var isComplete: Bool

    public init() {
        entries = []
        loadedPages = 0
        isComplete = false
    }

    /// The page "Load Older" asks for.
    public var nextPage: Int? { isComplete ? nil : loadedPages + 1 }

    /// Page `number` with its `listed` count — how many zKillboard named, before any body that
    /// could not be fetched was left out — appended. Listed once by id, newest first.
    public func appending(_ page: [KillboardEntry], number: Int, listed: Int) -> KillboardResults {
        var result = self
        var seen = Set(entries.map(\.id))
        result.entries += page.filter { seen.insert($0.id).inserted }
        result.entries.sort { ($0.killmail.time, $0.id) > ($1.killmail.time, $1.id) }
        result.loadedPages = max(loadedPages, number)
        result.isComplete = listed < Self.pageSize || result.loadedPages >= Self.maxPage
        return result
    }
}

/// One UTC day of results, `2026.10.17 · 12`.
public struct KillboardDay: Sendable, Hashable, Identifiable {
    /// Midnight UTC of the day.
    public var day: Date
    /// Newest first.
    public var entries: [KillboardEntry]

    public var id: Date { day }

    /// The entries by UTC day, newest day first, newest first within a day.
    public static func grouped(_ entries: [KillboardEntry]) -> [KillboardDay] {
        let calendar = Calendar.utc
        var days: [Date: [KillboardEntry]] = [:]
        for entry in entries {
            days[calendar.startOfDay(for: entry.killmail.time), default: []].append(entry)
        }
        return days.keys.sorted(by: >).map { day in
            KillboardDay(day: day, entries: days[day]!.sorted { ($0.killmail.time, $0.id) > ($1.killmail.time, $1.id) })
        }
    }
}

// MARK: - Killmail id

public enum KillboardKillmailID {
    /// The killmail id in what the player typed or pasted: a bare number, or a zKillboard
    /// link (`https://zkillboard.com/kill/139208025/`, with or without scheme, `www.` or the
    /// trailing slash). `nil` for anything else.
    public static func parse(_ text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int64(trimmed) { return id > 0 ? id : nil }

        var rest = Substring(trimmed.lowercased())
        for scheme in ["https://", "http://"] where rest.hasPrefix(scheme) {
            rest = rest.dropFirst(scheme.count)
        }
        if rest.hasPrefix("www.") { rest = rest.dropFirst(4) }
        guard rest.hasPrefix("zkillboard.com/") else { return nil }
        let path = rest.dropFirst("zkillboard.com/".count).prefix { $0 != "?" && $0 != "#" }
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count == 2, segments[0] == "kill", let id = Int64(segments[1]), id > 0 else { return nil }
        return id
    }
}

extension Calendar {
    /// Gregorian, UTC: EVE time.
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}
