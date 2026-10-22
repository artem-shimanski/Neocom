import Foundation
import KillmailKit
import Testing

private let me: Int64 = 90_000_001
private let vexor: Int64 = 626
private let blaster: Int64 = 3186
private let antimatter: Int64 = 23_009
private let ogre: Int64 = 2446
private let container: Int64 = 3465
private let paste: Int64 = 28_668
private let rig: Int64 = 31_360
private let base = Date(timeIntervalSince1970: 1_792_195_200) // 2026-10-17 00:00 UTC

private let prices: [Int64: Double] = [vexor: 10_000_000, blaster: 1_000_000, antimatter: 100, ogre: 500_000,
                                       container: 50_000, paste: 20_000, rig: 2_000_000]
private func price(_ typeID: Int64) -> Double? { prices[typeID] }

private func lossVexor(id: Int64 = 1, time: Date = base) -> Killmail {
    Killmail(
        id: id, hash: "h\(id)", time: time, solarSystemID: 30_002_811,
        victim: KillmailVictim(characterID: me, corporationID: 98_000_001, shipTypeID: vexor, damageTaken: 9897, items: [
            KillmailItem(typeID: antimatter, flag: 27, dropped: 38),
            KillmailItem(typeID: blaster, flag: 27, dropped: 1, singleton: 1),
            KillmailItem(typeID: blaster, flag: 28, destroyed: 1, singleton: 1),
            KillmailItem(typeID: rig, flag: 92, destroyed: 1, singleton: 1),
            KillmailItem(typeID: ogre, flag: 87, dropped: 2),
            KillmailItem(typeID: paste, flag: 5, destroyed: 10, dropped: 40),
            KillmailItem(typeID: container, flag: 5, destroyed: 1, singleton: 1, items: [
                KillmailItem(typeID: paste, flag: 5, dropped: 5),
            ]),
            KillmailItem(typeID: blaster, flag: 5, destroyed: 3, singleton: 2), // blueprint copy
            KillmailItem(typeID: 9899, flag: 89, destroyed: 1),
        ]),
        attackers: [
            KillmailAttacker(characterID: 91, corporationID: 92, shipTypeID: 11_989, damageDone: 3904),
            KillmailAttacker(characterID: 93, corporationID: 92, shipTypeID: 11_989, weaponTypeID: 3057, damageDone: 3893,
                             isFinalBlow: true),
            KillmailAttacker(corporationID: 1_000_125, shipTypeID: 30_000, weaponTypeID: 30_000, damageDone: 63),
            KillmailAttacker(characterID: 94, corporationID: 95, shipTypeID: 670, weaponTypeID: ogre, damageDone: 2037),
        ])
}

private func kill(id: Int64, time: Date, ship: Int64 = 670) -> Killmail {
    Killmail(id: id, hash: "h\(id)", time: time, solarSystemID: 30_002_811,
             victim: KillmailVictim(characterID: 96, shipTypeID: ship, damageTaken: 400),
             attackers: [KillmailAttacker(characterID: me, shipTypeID: vexor, damageDone: 400, isFinalBlow: true)])
}

@Suite struct SideTests {
    @Test func lossWhenVictimKillOtherwise() {
        #expect(lossVexor().side(for: me) == .loss)
        #expect(kill(id: 2, time: base).side(for: me) == .kill)
        #expect(lossVexor().side(for: 12345) == .kill)
    }
}

@Suite struct ItemTests {
    @Test func sectionsByFlag() {
        #expect(KillmailSection.of(flag: 27) == .high)
        #expect(KillmailSection.of(flag: 34) == .high)
        #expect(KillmailSection.of(flag: 19) == .medium)
        #expect(KillmailSection.of(flag: 18) == .low)
        #expect(KillmailSection.of(flag: 99) == .rig)
        #expect(KillmailSection.of(flag: 87) == .droneBay)
        #expect(KillmailSection.of(flag: 5) == .cargo)
        #expect(KillmailSection.of(flag: 89) == .implant)
        #expect(KillmailSection.of(flag: 133) == .other)
    }

    @Test func groupsWithLoadedChargesAndContainers() {
        let groups = lossVexor().itemGroups(isCharge: { $0 == antimatter || $0 == paste })
        #expect(groups.map(\.section) == [.high, .rig, .droneBay, .cargo, .implant])
        let high = groups[0]
        #expect(high.rows.map(\.item.typeID) == [blaster, antimatter, blaster])
        #expect(high.rows.map(\.isLoaded) == [false, true, false])
        #expect(high.rows.map(\.depth) == [0, 1, 0])
        #expect(high.topLevelCount == 2)
        let cargo = groups[3]
        #expect(cargo.rows.map(\.item.typeID) == [paste, container, paste, blaster])
        #expect(cargo.rows.map(\.depth) == [0, 0, 1, 0])
        #expect(cargo.topLevelCount == 3)
    }

    @Test func chargeHeuristicWithoutPredicate() {
        let groups = lossVexor().itemGroups()
        #expect(groups[0].rows.map(\.item.typeID) == [blaster, antimatter, blaster])
        #expect(groups[0].rows.map(\.isLoaded) == [false, true, false])
    }

    @Test func valueSplitsDestroyedAndDropped() {
        let value = lossVexor().value(price: price)
        // Hull 10M + blaster 1M + rig 2M + paste 10×20k + container 50k = 13.25M destroyed;
        // the BPC and the unpriced implant count nothing.
        #expect(value.destroyed == 13_250_000)
        // Charges 38×100 + blaster 1M + ogres 2×500k + paste 40×20k + nested paste 5×20k.
        #expect(value.dropped == 3_800 + 1_000_000 + 1_000_000 + 800_000 + 100_000)
        #expect(value.total == value.destroyed + value.dropped)
    }

    @Test func fitItemsUseFittingFlags() {
        let items = lossVexor().fitItems
        #expect(items.contains(KillmailFitItem(typeID: blaster, flag: "HiSlot0", quantity: 1)))
        #expect(items.contains(KillmailFitItem(typeID: antimatter, flag: "HiSlot0", quantity: 38)))
        #expect(items.contains(KillmailFitItem(typeID: blaster, flag: "HiSlot1", quantity: 1)))
        #expect(items.contains(KillmailFitItem(typeID: rig, flag: "RigSlot0", quantity: 1)))
        #expect(items.contains(KillmailFitItem(typeID: ogre, flag: "DroneBay", quantity: 2)))
        // Implants, cargo and containers' contents stay out.
        #expect(!items.contains { $0.typeID == 9899 })
        #expect(!items.contains { $0.flag == "Cargo" })
        #expect(!items.contains { $0.typeID == paste || $0.typeID == container })
        #expect(kill(id: 2, time: base).fitItems.isEmpty)
    }
}

@Suite struct AttackerTests {
    @Test func rankedByDamageWithShares() {
        let killmail = lossVexor()
        let ranked = killmail.rankedAttackers
        #expect(ranked.map(\.index) == [0, 1, 3, 2])
        #expect(ranked[0].isTopDamage && !ranked[1].isTopDamage)
        #expect(ranked[1].isFinalBlow)
        #expect(abs(ranked[0].share - 3904.0 / 9897.0) < 1e-9)
        #expect(killmail.finalBlow?.characterID == 93)
        #expect(killmail.leadingAttackers.map(\.index) == [1, 0])
        // One attacker both final blow and top damage: the next one fills the second row.
        let two = Killmail(id: 3, hash: "h3", time: base, solarSystemID: 1,
                           victim: KillmailVictim(characterID: 96, shipTypeID: 670, damageTaken: 412),
                           attackers: [KillmailAttacker(characterID: 97, damageDone: 114),
                                       KillmailAttacker(characterID: me, damageDone: 298, isFinalBlow: true)])
        #expect(two.leadingAttackers.map(\.index) == [1, 0])
        #expect(kill(id: 2, time: base).leadingAttackers.count == 1)
        #expect(killmail.involvedCount == 4)
        #expect(!killmail.isSolo)
        #expect(killmail.attackerSummary == KillmailAttackerSummary(involved: 4, pilots: 3, npc: 1, damage: 9897))
    }

    @Test func weaponSameAsShipIsNoWeapon() {
        let attackers = lossVexor().attackers
        #expect(attackers[0].separateWeaponTypeID == nil)
        #expect(attackers[1].separateWeaponTypeID == 3057)
        #expect(attackers[2].separateWeaponTypeID == nil)
        #expect(attackers[2].isNPC)
    }

    @Test func zeroDamageTakenFallsBackToAttackers() {
        var killmail = kill(id: 2, time: base)
        killmail.victim.damageTaken = 0
        #expect(killmail.damageShare(of: killmail.attackers[0]) == 1)
        #expect(killmail.isSolo)
    }
}

@Suite struct ListTests {
    @Test func pagingKeepsOlderPagesAndDedupes() {
        let first = KillmailRecentList().refreshed(withFirstPage: [.init(id: 10, hash: "a"), .init(id: 9, hash: "b")], pages: 2)
        #expect(first.hasMore && first.nextPage == 2)
        let more = first.appending(page: [.init(id: 9, hash: "b"), .init(id: 5, hash: "c")], number: 2, pages: 2)
        #expect(more.refs.map(\.id) == [10, 9, 5])
        #expect(!more.hasMore && more.nextPage == nil)
        let refreshed = more.refreshed(withFirstPage: [.init(id: 11, hash: "d"), .init(id: 10, hash: "a")], pages: 2)
        #expect(refreshed.refs.map(\.id) == [11, 10, 9, 5])
        #expect(refreshed.loadedPages == 2)
    }

    @Test func refreshStartsOverWhenPagesNoLongerJoinUp() {
        let loaded = KillmailRecentList().refreshed(withFirstPage: [.init(id: 10, hash: "a")], pages: 3)
            .appending(page: [.init(id: 8, hash: "b")], number: 2, pages: 3)
        #expect(loaded.refs.map(\.id) == [10, 8] && loaded.nextPage == 3)
        // More new killmails than a page holds: page 1 shares nothing with what was loaded.
        let gap = loaded.refreshed(withFirstPage: [.init(id: 20, hash: "c"), .init(id: 19, hash: "d")], pages: 4)
        #expect(gap.refs.map(\.id) == [20, 19])
        #expect(gap.loadedPages == 1 && gap.nextPage == 2)
        // A single page is the whole list: whatever left the 90 days goes.
        let single = loaded.refreshed(withFirstPage: [.init(id: 10, hash: "a")], pages: 1)
        #expect(single.refs.map(\.id) == [10])
        #expect(!single.hasMore)
    }

    @Test func statsAndFilter() {
        let all = [lossVexor(id: 1), kill(id: 2, time: base), kill(id: 3, time: base, ship: vexor)]
        let counts = KillmailListStats(all, pilotID: me)
        #expect(counts.kills == 2 && counts.losses == 1)
        let stats = KillmailListStats(all, pilotID: me, price: price)
        #expect(stats.iskLost == lossVexor().value(price: price).total)
        #expect(stats.iskDestroyed == 10_000_000)
        #expect(stats.count(for: .all) == 3)
        #expect(KillmailFilter.losses.apply(all, pilotID: me).map(\.id) == [1])
        #expect(KillmailFilter.kills.apply(all, pilotID: me).map(\.id) == [2, 3])
    }

    @Test func groupedByUTCDay() {
        let late = base.addingTimeInterval(-60) // 2026-10-16 23:59 UTC
        let days = KillmailDay.grouped([kill(id: 1, time: late), kill(id: 3, time: base.addingTimeInterval(3600)),
                                        kill(id: 2, time: base)])
        #expect(days.count == 2)
        #expect(days[0].day == base)
        #expect(days[0].killmails.map(\.id) == [3, 2])
        #expect(days[1].killmails.map(\.id) == [1])
    }
}
