import BusinessKit
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_792_238_400) // 2026-10-17 12:00 UTC
private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400

private func order(_ id: Int64, buy: Bool = false, price: Double = 100, remain: Int64 = 5, total: Int64 = 10,
                   issued: Date = now.addingTimeInterval(-day), duration: Int = 30, escrow: Double? = nil,
                   state: CharacterOrder.State = .open) -> CharacterOrder {
    CharacterOrder(id: id, typeID: 34, regionID: 10_000_030, locationID: 60_004_588, isBuyOrder: buy,
                   price: price, volumeRemain: remain, volumeTotal: total, duration: duration, issued: issued,
                   escrow: escrow, state: state)
}

@Suite struct OrderTests {
    @Test func expiryAndTimeLeft() {
        let o = order(1, issued: now.addingTimeInterval(-13.5 * day), duration: 14)
        #expect(o.expires == now.addingTimeInterval(0.5 * day))
        #expect(o.timeLeft(at: now) == 0.5 * day)
        #expect(o.isExpiringSoon(at: now))
        #expect(!order(2).isExpiringSoon(at: now))
        #expect(order(3, issued: now.addingTimeInterval(-40 * day)).timeLeft(at: now) == 0)
    }

    @Test func outcomes() {
        #expect(order(1).outcome == .open)
        #expect(order(2, remain: 0, state: .expired).outcome == .filled)
        #expect(order(3, remain: 4, state: .expired).outcome == .expired)
        #expect(order(4, remain: 0, state: .cancelled).outcome == .cancelled)
        // History is never flagged as expiring.
        #expect(!order(5, issued: now.addingTimeInterval(-29.9 * day), state: .expired).isExpiringSoon(at: now))
    }

    @Test func fractions() {
        let o = order(1, price: 2.5, remain: 3, total: 12)
        #expect(o.volumeTraded == 9)
        #expect(o.remainingFraction == 0.25)
        #expect(o.remainingValue == 7.5)
        #expect(order(2, remain: 0, total: 0).remainingFraction == 0)
    }

    @Test func summaryCountsOpenOnly() {
        let orders = [
            order(1, price: 10, remain: 2),
            order(2, price: 5, remain: 4, issued: now.addingTimeInterval(-29.5 * day)),
            order(3, buy: true, price: 3, remain: 10, escrow: 30),
            order(4, buy: true, price: 1, remain: 1),
            order(5, price: 1000, remain: 1, state: .expired),
        ]
        let summary = OrdersSummary(orders, now: now)
        #expect(summary.openCount == 4)
        #expect(summary.sellCount == 2)
        #expect(summary.buyCount == 2)
        #expect(summary.sellTotal == 40)
        #expect(summary.buyTotal == 31)
        #expect(summary.escrow == 30)
        #expect(summary.expiringSoonCount == 1)
    }

    @Test func bookPositionOfSellOrder() throws {
        let mine = order(1, price: 9_250_000)
        let book = [BookOrder(id: 1, isBuyOrder: false, price: 9_250_000),
                    BookOrder(id: 2, isBuyOrder: false, price: 9_200_000),
                    BookOrder(id: 3, isBuyOrder: false, price: 9_250_000),
                    BookOrder(id: 4, isBuyOrder: false, price: 9_900_000),
                    BookOrder(id: 5, isBuyOrder: true, price: 9_000_000)]
        let position = OrderBookPosition(of: mine, in: book)
        #expect(position.rank == 2)
        #expect(position.count == 4)
        #expect(position.bestOrderID == 2)
        #expect(position.bestPrice == 9_200_000)
        #expect(abs(position.gapToBest - 0.0054347826) < 1e-9)
        #expect(mine.flag(position: position, now: now) == .undercut)
    }

    @Test func bookPositionOfBuyOrderMissingFromBook() {
        let mine = order(1, buy: true, price: 100)
        let book = [BookOrder(id: 2, isBuyOrder: true, price: 100),
                    BookOrder(id: 3, isBuyOrder: true, price: 90),
                    BookOrder(id: 4, isBuyOrder: false, price: 120)]
        let position = OrderBookPosition(of: mine, in: book)
        // A tie is not better; the order counts itself even when the book lags behind.
        #expect(position.isFirst)
        #expect(position.count == 3)
        #expect(position.bestOrderID == nil)
        #expect(position.gapToBest == 0)
        #expect(mine.flag(position: position, now: now) == nil)

        let outbid = OrderBookPosition(of: mine, in: book + [BookOrder(id: 9, isBuyOrder: true, price: 101)])
        #expect(mine.flag(position: outbid, now: now) == .outbid)
    }

    @Test func ownOrdersDoNotUndercut() {
        let mine = order(1, price: 100)
        let book = [BookOrder(id: 1, isBuyOrder: false, price: 100),
                    BookOrder(id: 2, isBuyOrder: false, price: 95),
                    BookOrder(id: 3, isBuyOrder: false, price: 110)]
        // Order 2 is the same pilot's: it does not count against order 1.
        let position = OrderBookPosition(of: mine, in: book, ownOrderIDs: [1, 2])
        #expect(position.isFirst)
        #expect(position.count == 2)
        #expect(mine.flag(position: position, now: now) == nil)
        #expect(OrderBookPosition(of: mine, in: book).bestOrderID == 2)
    }

    @Test func flagFallsBackToExpiry() {
        let soon = order(1, issued: now.addingTimeInterval(-29.9 * day))
        #expect(soon.flag(position: nil, now: now) == .expiringSoon)
        #expect(order(2, state: .cancelled).flag(position: nil, now: now) == nil)
    }
}

private func job(_ id: Int64, activity: Int = 1, start: TimeInterval, end: TimeInterval, status: String,
                 pause: TimeInterval? = nil, completed: TimeInterval? = nil) -> IndustryJob {
    IndustryJob(id: id, activityID: activity, blueprintTypeID: 1, runs: 1,
                startDate: now.addingTimeInterval(start), endDate: now.addingTimeInterval(end),
                pauseDate: pause.map(now.addingTimeInterval), completedDate: completed.map(now.addingTimeInterval),
                status: status)
}

@Suite struct CorporationOrderTests {
    @Test func newFieldsRoundTrip() throws {
        let o = CharacterOrder(id: 1, typeID: 34, regionID: 1, locationID: 2, isBuyOrder: false, isCorporation: true,
                               price: 1, volumeRemain: 1, volumeTotal: 1, duration: 30, issued: now,
                               walletDivision: 3, issuedBy: 42)
        let decoded = try JSONDecoder().decode(CharacterOrder.self, from: JSONEncoder().encode(o))
        #expect(decoded == o)
        #expect(decoded.walletDivision == 3)
        #expect(decoded.issuedBy == 42)
    }

    @Test func oldCacheWithoutTheNewKeysDecodes() throws {
        let json = """
        {"id":1,"typeID":34,"regionID":1,"locationID":2,"isBuyOrder":true,"isCorporation":false,
         "price":5,"volumeRemain":1,"volumeTotal":2,"minVolume":1,"range":"region","duration":30,
         "issued":0,"state":"open"}
        """
        let decoded = try JSONDecoder().decode(CharacterOrder.self, from: Data(json.utf8))
        #expect(decoded.walletDivision == nil)
        #expect(decoded.issuedBy == nil)
        #expect(order(2).walletDivision == nil)
    }
}

@Suite struct IndustryTests {
    @Test func activities() {
        #expect(IndustryActivity(activityID: 1) == .manufacturing)
        #expect(IndustryActivity(activityID: 3) == .researchTime)
        #expect(IndustryActivity(activityID: 4) == .researchMaterial)
        #expect(IndustryActivity(activityID: 5) == .copying)
        #expect(IndustryActivity(activityID: 8) == .invention)
        #expect(IndustryActivity(activityID: 9) == .reaction)
        #expect(IndustryActivity(activityID: 11) == .reaction)
        #expect(IndustryActivity(activityID: 42) == .unknown)
        #expect(IndustryActivity.copying.runUnit == .copies)
        #expect(IndustryActivity.researchMaterial.runUnit == .levels)
    }

    @Test func activeJobPastItsEndIsReady() {
        let done = job(1, start: -4 * hour, end: -1 * hour, status: "active")
        #expect(done.phase(at: now) == .ready)
        #expect(done.progress(at: now) == 1)
        #expect(done.timeLeft(at: now) == 0)
        #expect(done.timeSinceEnd(at: now) == hour)
        #expect(job(2, start: 0, end: 1, status: "ready").phase(at: now) == .ready)
    }

    @Test func progressAgainstTheClock() {
        let running = job(1, start: -1 * hour, end: 3 * hour, status: "active")
        #expect(running.phase(at: now) == .active)
        #expect(running.progress(at: now) == 0.25)
        #expect(running.timeLeft(at: now) == 3 * hour)
    }

    @Test func pausedJobFreezesAtThePause() {
        let paused = job(1, start: -10 * hour, end: 10 * hour, status: "paused", pause: -5 * hour)
        #expect(paused.phase(at: now) == .paused)
        #expect(paused.progress(at: now) == 0.25)
        #expect(paused.timeLeft(at: now) == 15 * hour)
    }

    @Test func completedJobs() {
        let cancelled = job(1, start: -10 * hour, end: 10 * hour, status: "cancelled", completed: -5 * hour)
        #expect(cancelled.phase(at: now).isCompleted)
        #expect(cancelled.progress(at: now) == 0.25)
        #expect(job(2, start: -2 * hour, end: -1 * hour, status: "delivered").progress(at: now) == 1)
        #expect(job(3, start: -2 * hour, end: -1 * hour, status: "reverted").progress(at: now) == 0)
        #expect(job(4, start: 0, end: 1, status: "weird").phase(at: now) == .unknown)
    }

    @Test func summary() {
        let jobs = [
            job(1, start: -4 * hour, end: -1 * hour, status: "active"),
            job(2, start: -1 * hour, end: 5 * hour, status: "active"),
            job(3, start: -1 * hour, end: 2 * hour, status: "active"),
            job(4, start: -1 * hour, end: 2 * hour, status: "paused", pause: -0.5 * hour),
            job(5, start: -9 * hour, end: -8 * hour, status: "delivered", completed: -7 * hour),
            job(6, start: -9 * hour, end: -8 * hour, status: "cancelled", completed: -6 * hour),
        ]
        let summary = IndustrySummary(jobs, now: now)
        #expect(summary.readyCount == 1)
        #expect(summary.activeCount == 2)
        #expect(summary.pausedCount == 1)
        #expect(summary.nextCompletion == now.addingTimeInterval(2 * hour))
        #expect(jobs.activeSortedByEnd(at: now).map(\.id) == [3, 2])
        #expect(jobs.completedLatestFirst(at: now).map(\.id) == [6, 5])
        #expect(IndustrySummary([], now: now).nextCompletion == nil)
    }
}

private let me: Int64 = 90_000_001

private func contract(_ id: Int64, type: String = "item_exchange", status: String = "outstanding",
                      issuer: Int64 = me, assignee: Int64 = 0, acceptor: Int64 = 0,
                      expires: TimeInterval = 5 * day, accepted: TimeInterval? = nil, days: Int? = nil,
                      price: Double? = nil, buyout: Double? = nil) -> Contract {
    Contract(id: id, type: type, status: status, issuerID: issuer, assigneeID: assignee, acceptorID: acceptor,
             dateIssued: now.addingTimeInterval(-day), dateExpired: now.addingTimeInterval(expires),
             dateAccepted: accepted.map(now.addingTimeInterval), daysToComplete: days, price: price, buyout: buyout)
}

@Suite struct ContractTests {
    @Test func rawValuesAndUnknowns() {
        #expect(contract(1, type: "courier").kind == .courier)
        #expect(contract(2, type: "something_new").kind == .unknown)
        #expect(contract(3, status: "finished_contractor").status == .finishedContractor)
        #expect(contract(4, status: "nope").status == .unknown)
        #expect(ContractStatus.reversed.tone == .failed)
        #expect(ContractStatus.deleted.tone == .closed)
        #expect(ContractAvailability(raw: "public") == .public)
    }

    @Test func roles() {
        let offered = contract(1, issuer: 7, assignee: me)
        #expect(offered.roles(of: me) == .assignee)
        #expect(offered.isOfferedTo(me))
        #expect(offered.isForMe(me))
        let mine = contract(2)
        #expect(mine.roles(of: me) == .issuer)
        #expect(!mine.isForMe(me))
        let carried = contract(3, type: "courier", status: "in_progress", issuer: 7, acceptor: me)
        #expect(carried.isForMe(me))
        #expect(!carried.isOfferedTo(me))
        // Nobody is id 0.
        #expect(contract(4, issuer: 7).roles(of: 0) == [])
    }

    @Test func courierDeadline() throws {
        let courier = contract(1, type: "courier", status: "in_progress", issuer: 7, acceptor: me,
                               expires: 6 * day, accepted: -2 * day, days: 3)
        #expect(courier.deadline == now.addingTimeInterval(day))
        #expect(courier.activeDue == now.addingTimeInterval(day))
        #expect(courier.timeLeft(at: now) == day)
        #expect(!courier.isDueSoon(at: now))
        #expect(courier.isDueSoon(at: now.addingTimeInterval(hour)))
        #expect(contract(2, type: "item_exchange", accepted: -day, days: 3).deadline == nil)
    }

    @Test func courierOverdue() {
        let courier = contract(1, type: "courier", status: "in_progress", issuer: 7, acceptor: me,
                               expires: 6 * day, accepted: -4 * day, days: 3)
        #expect(courier.isOverdue(at: now))
        #expect(courier.timeLeft(at: now) == 0)
        #expect(!courier.isDueSoon(at: now))
        #expect(!courier.isOverdue(at: now.addingTimeInterval(-2 * day)))
        // Outstanding past its expiry is expired, not overdue.
        #expect(!contract(2, type: "courier", expires: -hour).isOverdue(at: now))
    }

    @Test func expiry() {
        let expired = contract(1, expires: -hour)
        #expect(expired.isExpired(at: now))
        #expect(expired.timeLeft(at: now) == 0)
        #expect(!contract(2, status: "finished", expires: -hour).isExpired(at: now))
        #expect(contract(3, status: "finished").activeDue == nil)
    }

    @Test func summary() {
        let contracts = [
            contract(1, issuer: 7, assignee: me),
            contract(2),
            contract(3, type: "courier", status: "in_progress", issuer: 7, acceptor: me),
            contract(4, status: "finished"),
            contract(5, status: "rejected", issuer: 7, assignee: me),
        ]
        let summary = ContractsSummary(contracts, characterID: me)
        #expect(summary.activeCount == 3)
        #expect(summary.finishedCount == 2)
        #expect(summary.outstandingCount == 2)
        #expect(summary.inProgressCount == 1)
        #expect(summary.toYouCount == 1)
    }

    @Test func corporationRelations() {
        func corp(_ id: Int64, status: String = "outstanding", issuerCorp: Int64 = 7, forCorp: Bool = false,
                  assignee: Int64 = 0, acceptor: Int64 = 0) -> Contract {
            Contract(id: id, type: "courier", status: status, issuerID: 1, issuerCorporationID: issuerCorp,
                     assigneeID: assignee, acceptorID: acceptor, forCorporation: forCorp,
                     dateIssued: now, dateExpired: now.addingTimeInterval(day))
        }
        let corporation: Int64 = 98_000_001
        #expect(corp(1, issuerCorp: corporation, forCorp: true).isIssuedByCorporation(corporation))
        #expect(!corp(2, issuerCorp: corporation).isIssuedByCorporation(corporation))
        #expect(!corp(3, issuerCorp: 5, forCorp: true).isIssuedByCorporation(corporation))

        #expect(corp(4, assignee: corporation).isForCorporation(corporation))
        #expect(corp(5, status: "in_progress", acceptor: corporation).isForCorporation(corporation))
        #expect(!corp(6, status: "finished", assignee: corporation).isForCorporation(corporation))
        #expect(!corp(7, issuerCorp: corporation, forCorp: true, assignee: corporation).isForCorporation(corporation))
        #expect(!corp(8).isForCorporation(corporation))

        let summary = ContractsSummary([
            corp(10, assignee: corporation),
            corp(11, issuerCorp: corporation, forCorp: true),
            corp(12, status: "in_progress", acceptor: corporation),
            corp(13, status: "finished", assignee: corporation),
            corp(14, issuerCorp: corporation, forCorp: true, assignee: corporation),
        ], corporationID: corporation)
        #expect(summary.activeCount == 4)
        #expect(summary.finishedCount == 1)
        #expect(summary.outstandingCount == 3)
        #expect(summary.inProgressCount == 1)
        #expect(summary.toYouCount == 1)
    }

    @Test func bidsAndAuctionProgress() throws {
        let bids = [ContractBid(id: 1, bidderID: 1, amount: 2_000_000, date: now.addingTimeInterval(-3 * day)),
                    ContractBid(id: 2, bidderID: 2, amount: 3_150_000, date: now.addingTimeInterval(-hour)),
                    ContractBid(id: 3, bidderID: 3, amount: 3_150_000, date: now.addingTimeInterval(-2 * hour))]
        #expect(bids.highestFirst.map(\.id) == [3, 2, 1])
        let auction = contract(1, type: "auction", price: 2_000_000, buyout: 6_500_000)
        let progress = try #require(auction.auctionProgress(highBid: bids.highest?.amount))
        #expect(abs(progress - 1_150_000 / 4_500_000) < 1e-12)
        #expect(auction.auctionProgress(highBid: nil) == 0)
        #expect(auction.auctionProgress(highBid: 9_000_000) == 1)
        #expect(contract(2, type: "auction", price: 1).auctionProgress(highBid: 2) == nil)
    }

    @Test func blueprintCopy() {
        #expect(ContractItem(id: 1, typeID: 1, quantity: 1, rawQuantity: -2, isSingleton: true).isBlueprintCopy)
        #expect(!ContractItem(id: 2, typeID: 1, quantity: 1, rawQuantity: -1, isSingleton: true).isBlueprintCopy)
    }
}
