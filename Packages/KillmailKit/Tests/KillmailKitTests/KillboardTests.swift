import Foundation
import KillmailKit
import Testing

private let day = Date(timeIntervalSince1970: 1_792_195_200) // 2026-10-17 00:00 UTC

private func killmail(_ id: Int64, at time: Date, character: Int64? = 1, corporation: Int64? = 2,
                      alliance: Int64? = 3, faction: Int64? = nil, ship: Int64 = 626) -> Killmail {
    Killmail(id: id, hash: "h\(id)", time: time, solarSystemID: 30_002_811,
             victim: KillmailVictim(characterID: character, corporationID: corporation, allianceID: alliance,
                                    factionID: faction, shipTypeID: ship, damageTaken: 100),
             attackers: [KillmailAttacker(characterID: 9, damageDone: 100, isFinalBlow: true)])
}

private func entry(_ id: Int64, at time: Date) -> KillboardEntry {
    KillboardEntry(killmail: killmail(id, at: time))
}

@Suite struct KillboardSubjectTests {
    @Test func sideFromSubject() {
        let mail = killmail(1, at: day, character: 10, corporation: 20, alliance: 30, faction: 40, ship: 626)
        #expect(KillboardSubject(kind: .character, id: 10, name: "").side(of: mail) == .loss)
        #expect(KillboardSubject(kind: .character, id: 11, name: "").side(of: mail) == .kill)
        #expect(KillboardSubject(kind: .corporation, id: 20, name: "").side(of: mail) == .loss)
        #expect(KillboardSubject(kind: .alliance, id: 31, name: "").side(of: mail) == .kill)
        #expect(KillboardSubject(kind: .faction, id: 40, name: "").side(of: mail) == .loss)
        #expect(KillboardSubject(kind: .shipType, id: 626, name: "Vexor").side(of: mail) == .loss)
        #expect(KillboardSubject(kind: .shipType, id: 627, name: "").side(of: mail) == .kill)
        let cruisers = KillboardSubject(kind: .shipGroup, id: 26, name: "Cruiser")
        #expect(cruisers.side(of: mail) { $0 == 626 ? 26 : nil } == .loss)
        #expect(cruisers.side(of: mail) { _ in 25 } == .kill)
        #expect(KillboardSubject(kind: .solarSystem, id: 30_002_811, name: "").side(of: mail) == nil)
        #expect(KillboardSubject(kind: .region, id: 1, name: "").side(of: mail) == nil)
    }

    @Test func unknownGroupHasNoSide() {
        let mail = killmail(1, at: day, ship: 626)
        let cruisers = KillboardSubject(kind: .shipGroup, id: 26, name: "Cruiser")
        #expect(cruisers.side(of: mail) == nil)
        #expect(cruisers.side(of: mail) { _ in nil } == nil)
    }

    @Test func requestedSideWins() {
        // A Vexor killed by a Vexor: a loss by its victim, but in a Vexor's kills it is a kill.
        let mail = killmail(1, at: day, ship: 626)
        let vexor = KillboardSubject(kind: .shipType, id: 626, name: "Vexor")
        #expect(KillboardCriteria(subject: vexor, side: .kills).side(of: mail) == .kill)
        #expect(KillboardCriteria(subject: vexor, side: .losses).side(of: mail) == .loss)
        #expect(KillboardCriteria(subject: vexor, side: .all).side(of: mail) == .loss)
        let other = killmail(2, at: day, ship: 627)
        #expect(KillboardCriteria(subject: vexor, side: .losses).side(of: other) == .loss)
        #expect(KillboardCriteria(subject: vexor, side: .all).side(of: other) == .kill)
        // Unknown group: no side for both, the asked side otherwise.
        let cruisers = KillboardSubject(kind: .shipGroup, id: 26, name: "Cruiser")
        #expect(KillboardCriteria(subject: cruisers, side: .all).side(of: mail) == nil)
        #expect(KillboardCriteria(subject: cruisers, side: .kills).side(of: mail) == .kill)
        // A place has no side, whatever was set; no subject, none either.
        let system = KillboardSubject(kind: .solarSystem, id: 30_002_811, name: "")
        #expect(KillboardCriteria(subject: system, side: .kills).side(of: mail) == nil)
        #expect(KillboardCriteria(side: .losses).side(of: mail) == nil)
    }
}

@Suite struct KillboardCriteriaTests {
    @Test func noSubjectNoQuery() {
        #expect(KillboardCriteria().parameters() == nil)
        #expect(!KillboardCriteria().canSearch)
    }

    @Test func fullQuery() throws {
        let criteria = KillboardCriteria(subject: KillboardSubject(kind: .shipType, id: 626, name: "Vexor"),
                                         side: .losses, space: .lowsec, engagement: .solo, npc: .excluded,
                                         awox: .only, period: .pastWeek, minimumValue: 1_000_000_000,
                                         finalBlowOnly: true)
        let query = try #require(criteria.parameters(page: 3))
        #expect(query.subject == .shipType)
        #expect(query.subjectID == 626)
        #expect(query.side == .losses)
        #expect(query.space == .lowsec)
        #expect(query.engagement == .solo)
        #expect(query.npc == false)
        #expect(query.awox == true)
        #expect(query.finalBlowOnly)
        #expect(query.minimumValue == 1_000_000_000)
        #expect(query.pastSeconds == 604_800)
        #expect(query.month == nil)
        #expect(query.page == 3)
    }

    @Test func placeDropsSideAndFinalBlow() throws {
        let criteria = KillboardCriteria(subject: KillboardSubject(kind: .solarSystem, id: 30_000_142, name: "Jita"),
                                         side: .kills, period: .month(year: 2026, month: 9), finalBlowOnly: true)
        let query = try #require(criteria.parameters())
        #expect(query.side == .all)
        #expect(!query.finalBlowOnly)
        #expect(query.pastSeconds == nil)
        #expect(query.month == .init(year: 2026, month: 9))
        #expect(query.npc == nil && query.awox == nil)
        #expect(query.page == 1)
    }

    @Test func valueRoundedAndPageClamped() throws {
        let subject = KillboardSubject(kind: .character, id: 1, name: "")
        #expect(KillboardCriteria(subject: subject, minimumValue: 1_200_000_000).parameters()?.minimumValue == 1_000_000_000)
        #expect(KillboardCriteria(subject: subject, minimumValue: 100_000_000).parameters()?.minimumValue == nil)
        #expect(KillboardCriteria(subject: subject).parameters(page: 500)?.page == 100)
        #expect(KillboardCriteria.minimumValueOptions.allSatisfy { $0 % 500_000_000 == 0 })
    }

    @Test func periods() {
        #expect(KillboardPeriod.pastHour.pastSeconds == 3600)
        #expect(KillboardPeriod.pastDay.pastSeconds == 86_400)
        #expect(KillboardPeriod.any.pastSeconds == nil)
        #expect(KillboardPeriod.recentMonths(3, now: day) == [
            .month(year: 2026, month: 10), .month(year: 2026, month: 9), .month(year: 2026, month: 8),
        ])
        let january = Date(timeIntervalSince1970: 1_767_312_000) // 2026-01-02 UTC
        #expect(KillboardPeriod.recentMonths(2, now: january) == [.month(year: 2026, month: 1), .month(year: 2025, month: 12)])
    }
}

@Suite struct KillboardResultsTests {
    @Test func pagingStopsOnShortPage() {
        var results = KillboardResults()
        #expect(results.nextPage == 1)
        let full = (0..<200).map { entry(Int64(1000 - $0), at: day.addingTimeInterval(Double(-$0) * 60)) }
        results = results.appending(full, number: 1, listed: 200)
        #expect(results.nextPage == 2)
        #expect(results.entries.count == 200)
        // A repeated row (the list shifted) is listed once; bodies left out still count as listed.
        let short = [entry(801, at: day.addingTimeInterval(-200 * 60)), entry(700, at: day.addingTimeInterval(-300 * 60))]
        results = results.appending(short, number: 2, listed: 3)
        #expect(results.entries.count == 201)
        #expect(results.isComplete)
        #expect(results.nextPage == nil)
        #expect(results.entries.first?.id == 1000)
        #expect(results.entries.last?.id == 700)
    }

    @Test func emptyFirstPageIsComplete() {
        let results = KillboardResults().appending([], number: 1, listed: 0)
        #expect(results.isComplete)
        #expect(results.entries.isEmpty)
    }

    @Test func lastPageIsComplete() {
        let page = (0..<200).map { entry(Int64(200 - $0), at: day) }
        #expect(KillboardResults().appending(page, number: 100, listed: 200).isComplete)
    }

    @Test func groupedByUTCDay() {
        let entries = [
            entry(1, at: day.addingTimeInterval(-60)), // 2026-10-16 23:59
            entry(2, at: day.addingTimeInterval(60)),
            entry(3, at: day.addingTimeInterval(3600)),
        ]
        let days = KillboardDay.grouped(entries)
        #expect(days.map(\.day) == [day, day.addingTimeInterval(-86_400)])
        #expect(days[0].entries.map(\.id) == [3, 2])
        #expect(days[1].entries.map(\.id) == [1])
        #expect(entries[0].involved == 1)
    }
}

@Suite struct KillboardKillmailIDTests {
    @Test func parsesNumbersAndLinks() {
        #expect(KillboardKillmailID.parse("139208025") == 139_208_025)
        #expect(KillboardKillmailID.parse("  139208025\n") == 139_208_025)
        #expect(KillboardKillmailID.parse("https://zkillboard.com/kill/123456/") == 123_456)
        #expect(KillboardKillmailID.parse("http://www.zkillboard.com/kill/123456") == 123_456)
        #expect(KillboardKillmailID.parse("zkillboard.com/kill/123456/?foo=bar") == 123_456)
        #expect(KillboardKillmailID.parse("HTTPS://zKillboard.com/kill/42/") == 42)
    }

    @Test func rejectsEverythingElse() {
        #expect(KillboardKillmailID.parse("") == nil)
        #expect(KillboardKillmailID.parse("0") == nil)
        #expect(KillboardKillmailID.parse("-5") == nil)
        #expect(KillboardKillmailID.parse("abc") == nil)
        #expect(KillboardKillmailID.parse("https://zkillboard.com/character/123456/") == nil)
        #expect(KillboardKillmailID.parse("https://evil.com/kill/123456/") == nil)
        #expect(KillboardKillmailID.parse("https://zkillboard.com/kill/12x/") == nil)
    }
}
