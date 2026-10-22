import BusinessKit
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_792_238_400) // 2026-10-17 12:00 UTC
private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400
private let me: Int64 = 90_000_001
private let other: Int64 = 90_000_002

private func job(_ id: Int64, end: TimeInterval, status: String = "active") -> IndustryJob {
    IndustryJob(id: id, activityID: 1, blueprintTypeID: 1, runs: 1, startDate: now.addingTimeInterval(-day),
                endDate: now.addingTimeInterval(end), status: status)
}

private func contract(_ id: Int64, type: String = "item_exchange", status: String = "outstanding",
                      issuer: Int64 = me, assignee: Int64 = 0, acceptor: Int64 = 0,
                      expires: TimeInterval = 5 * day, accepted: TimeInterval? = nil, days: Int? = nil) -> Contract {
    Contract(id: id, type: type, status: status, issuerID: issuer, assigneeID: assignee, acceptorID: acceptor,
             dateIssued: now.addingTimeInterval(-day), dateExpired: now.addingTimeInterval(expires),
             dateAccepted: accepted.map(now.addingTimeInterval), daysToComplete: days)
}

private func order(_ id: Int64, remain: Int64 = 5, state: CharacterOrder.State = .open) -> CharacterOrder {
    CharacterOrder(id: id, typeID: 34, regionID: 1, locationID: 1, isBuyOrder: false, price: 1,
                   volumeRemain: remain, volumeTotal: 10, duration: 30, issued: now.addingTimeInterval(-day),
                   state: state)
}

@Suite struct IndustryReminderTests {
    @Test func runningJobsSoonestFirst() {
        let jobs = [job(1, end: 5 * hour), job(2, end: hour), job(3, end: -hour), job(4, end: 2 * hour, status: "paused"),
                    job(5, end: 3 * hour, status: "delivered")]
        #expect(IndustryReminders.plan(jobs, now: now).map(\.id) == [2, 1])
    }
}

@Suite struct ContractReminderTests {
    @Test func expiriesAndDeadlines() {
        let contracts = [
            contract(1, expires: 4 * day),                                      // mine, outstanding
            contract(2, issuer: other, assignee: me, expires: 3 * hour),        // offered to me
            contract(3, issuer: other, expires: day),                           // someone else's public one
            contract(4, type: "courier", status: "in_progress", issuer: other, acceptor: me,
                     expires: 10 * day, accepted: -day, days: 3),               // I carry it
            contract(5, expires: 30 * 60),                                      // reminder already past
            contract(6, status: "finished", expires: day),
        ]
        let plan = ContractReminders.plan(contracts, characterID: me, now: now)
        #expect(plan.map(\.id) == ["expires.2", "courierDue.4", "expires.1"])
        #expect(plan[0].fireDate == now.addingTimeInterval(2 * hour))
        #expect(plan[1].eventDate == now.addingTimeInterval(2 * day))
    }
}

@Suite struct OrderWatchTests {
    @Test func firstCheckOnlyRecords() {
        let result = OrderWatch.check(open: [order(1), order(2)], history: [order(3, remain: 0, state: .expired)], baseline: nil)
        #expect(result.closed.isEmpty)
        #expect(result.baseline == [1, 2])
    }

    @Test func filledExpiredCancelledAndLagging() {
        let result = OrderWatch.check(
            open: [order(5)],
            history: [order(1, remain: 0, state: .expired), order(2, remain: 3, state: .expired),
                      order(3, state: .cancelled), order(9, remain: 0, state: .expired)],
            baseline: [1, 2, 3, 4])
        // 1 filled, 2 expired, 3 cancelled (silent), 4 not in history yet (kept), 9 never seen open.
        #expect(result.closed.map(\.id) == [1, 2])
        #expect(result.closed.map(\.outcome) == [.filled, .expired])
        #expect(result.baseline == [4, 5])
    }
}

@Suite struct ContractWatchTests {
    @Test func firstCheckOnlyRecords() {
        let result = ContractWatch.check([contract(1), contract(2, status: "finished")], characterID: me, baseline: nil)
        #expect(result.finished.isEmpty)
        #expect(result.baseline == [1: "outstanding"])
    }

    @Test func finishedSinceTheLastCheck() {
        let contracts = [
            contract(1, status: "finished"),
            contract(2, type: "courier", status: "failed", issuer: other, acceptor: me),
            contract(3, status: "deleted"),
            contract(4, status: "in_progress", issuer: other, acceptor: me),
            contract(5, status: "finished"),                                    // never seen active
            contract(6, status: "finished", issuer: other),                     // not mine
        ]
        let baseline: ContractWatch.Baseline = [1: "outstanding", 2: "in_progress", 3: "outstanding",
                                                4: "outstanding", 6: "outstanding"]
        let result = ContractWatch.check(contracts, characterID: me, baseline: baseline)
        #expect(result.finished.map(\.id) == [1, 2])
        #expect(result.baseline == [4: "in_progress"])
    }
}
