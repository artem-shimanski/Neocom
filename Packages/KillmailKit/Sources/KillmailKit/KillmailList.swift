// The pilot's recent killmails: paging, the kills/losses filter, the totals, the days.

import Foundation

/// The killmails `/characters/{id}/killmails/recent` has listed so far, newest first, and how
/// far the paging got. ESI keeps about the last 90 days there; older ones are not listed at
/// all.
public struct KillmailRecentList: Codable, Sendable, Hashable {
    public private(set) var refs: [KillmailRef]
    /// Pages fetched so far, from page 1.
    public private(set) var loadedPages: Int
    /// The page count ESI named last.
    public private(set) var totalPages: Int

    public init(refs: [KillmailRef] = [], loadedPages: Int = 0, totalPages: Int = 0) {
        self.refs = Self.ordered(refs)
        self.loadedPages = loadedPages
        self.totalPages = totalPages
    }

    /// Whether "Load Older" has anything to load.
    public var hasMore: Bool { loadedPages < totalPages }

    /// The page "Load Older" asks for.
    public var nextPage: Int? { hasMore ? loadedPages + 1 : nil }

    /// A refresh with a new page 1. Older loaded pages are kept while they join up with it;
    /// they are dropped and paging restarts when ESI now has a single page or when page 1
    /// shares no killmail with them (a gap that "Load Older" would skip).
    public func refreshed(withFirstPage page: [KillmailRef], pages: Int) -> KillmailRecentList {
        let pages = max(1, pages)
        let known = Set(refs.map(\.id))
        let joinsUp = page.contains { known.contains($0.id) }
        guard pages > 1, joinsUp else {
            return KillmailRecentList(refs: page, loadedPages: 1, totalPages: pages)
        }
        return KillmailRecentList(refs: page + refs, loadedPages: max(1, loadedPages), totalPages: pages)
    }

    /// The next older page, appended. Pages shift as new killmails arrive, so repeats are
    /// listed once.
    public func appending(page: [KillmailRef], number: Int, pages: Int) -> KillmailRecentList {
        KillmailRecentList(refs: refs + page, loadedPages: max(loadedPages, number), totalPages: max(1, pages))
    }

    /// Unique by id, newest first: ids grow with time.
    private static func ordered(_ refs: [KillmailRef]) -> [KillmailRef] {
        var seen: Set<Int64> = []
        return refs.filter { seen.insert($0.id).inserted }.sorted { $0.id > $1.id }
    }
}

/// `All · 6`, `Kills · 4`, `Losses · 2`.
public enum KillmailFilter: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case all
    case kills
    case losses

    public var id: Self { self }

    public func includes(_ side: KillmailSide) -> Bool {
        switch self {
        case .all: true
        case .kills: side == .kill
        case .losses: side == .loss
        }
    }

    public func apply(_ killmails: [Killmail], pilotID: Int64) -> [Killmail] {
        killmails.filter { includes($0.side(for: pilotID)) }
    }
}

/// `KILLS 4 · LOSSES 2 · DESTROYED 63.34M · LOST 39.36M`: the kills' worth is what the pilot
/// destroyed, the losses' what the pilot lost — both estimates from average prices.
public struct KillmailListStats: Sendable, Hashable {
    public var kills: Int
    public var losses: Int
    public var iskDestroyed: Double
    public var iskLost: Double

    public init(kills: Int = 0, losses: Int = 0, iskDestroyed: Double = 0, iskLost: Double = 0) {
        self.kills = kills
        self.losses = losses
        self.iskDestroyed = iskDestroyed
        self.iskLost = iskLost
    }

    /// The counts only — what the home tile shows, no prices needed.
    public init(_ killmails: [Killmail], pilotID: Int64) {
        let losses = killmails.count { $0.side(for: pilotID) == .loss }
        self.init(kills: killmails.count - losses, losses: losses)
    }

    /// Counts and worth, at `price`.
    public init(_ killmails: [Killmail], pilotID: Int64, price: (Int64) -> Double?) {
        self.init()
        for killmail in killmails {
            let total = killmail.value(price: price).total
            switch killmail.side(for: pilotID) {
            case .kill:
                kills += 1
                iskDestroyed += total
            case .loss:
                losses += 1
                iskLost += total
            }
        }
    }

    public func count(for filter: KillmailFilter) -> Int {
        switch filter {
        case .all: kills + losses
        case .kills: kills
        case .losses: losses
        }
    }
}

/// One day of the list, `2026.10.16`: EVE time, so the days are UTC days.
public struct KillmailDay: Sendable, Hashable, Identifiable {
    /// Midnight UTC of the day.
    public var day: Date
    /// Newest first.
    public var killmails: [Killmail]

    public var id: Date { day }

    /// The killmails by UTC day, newest day first, newest first within a day.
    public static func grouped(_ killmails: [Killmail]) -> [KillmailDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var days: [Date: [Killmail]] = [:]
        for killmail in killmails {
            days[calendar.startOfDay(for: killmail.time), default: []].append(killmail)
        }
        return days.keys.sorted(by: >).map { day in
            KillmailDay(day: day, killmails: days[day]!.sorted { ($0.time, $0.id) > ($1.time, $1.id) })
        }
    }
}
