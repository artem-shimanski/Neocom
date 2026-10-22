import Foundation
import MarketKit
import Testing

private func sell(_ id: Int64, _ price: Double, _ volume: Int64, system: Int64 = 1) -> MarketOrder {
    MarketOrder(id: id, isBuyOrder: false, price: price, volumeRemain: volume, locationID: 60_000_000 + id, systemID: system)
}

private func buy(_ id: Int64, _ price: Double, _ volume: Int64, minVolume: Int64 = 1, system: Int64 = 1) -> MarketOrder {
    MarketOrder(id: id, isBuyOrder: true, price: price, volumeRemain: volume, minVolume: minVolume,
                locationID: 1_000_000_000_000 + id, systemID: system)
}

private func day(_ string: String, average: Double, volume: Int64 = 10) -> MarketHistoryDay {
    MarketHistoryDay(date: MarketHistoryDay.date(fromESI: string)!, average: average,
                     lowest: average * 0.9, highest: average * 1.1, volume: volume, orderCount: 1)
}

@Suite struct OrderBookTests {
    let book = [sell(1, 105, 5), sell(2, 100, 3), buy(3, 90, 10), buy(4, 95, 2), sell(5, 100, 7)]

    @Test func bestPricesAndSpread() throws {
        #expect(MarketMath.bestSell(book) == 100)
        #expect(MarketMath.bestBuy(book) == 95)
        let spread = try #require(MarketMath.spread(bestSell: 100, bestBuy: 95))
        #expect(abs(spread - 0.05) < 1e-12)
        #expect(MarketMath.spread(bestSell: nil, bestBuy: 95) == nil)
    }

    @Test func sortedBestFirst() {
        #expect(MarketMath.sorted(book, side: .sell).map(\.id) == [2, 5, 1])
        #expect(MarketMath.sorted(book, side: .buy).map(\.id) == [4, 3])
    }

    @Test func fillWalksTheBook() {
        let sells = MarketMath.sorted(book, side: .sell)
        let fill = MarketMath.fill(12, from: sells)
        #expect(fill.filled == 12)
        #expect(fill.total == 3 * 100 + 7 * 100 + 2 * 105)
        #expect(fill.ordersUsed == 3)
        #expect(fill.worstPrice == 105)
        #expect(fill.isComplete)
    }

    @Test func fillRunsOutOfOrders() {
        let fill = MarketMath.fill(100, from: MarketMath.sorted(book, side: .sell))
        #expect(fill.filled == 15)
        #expect(!fill.isComplete)
        #expect(MarketMath.fill(0, from: book).filled == 0)
    }

    @Test func fillSkipsOrdersAboveMinimumVolume() {
        let buys = [buy(1, 100, 50, minVolume: 10), buy(2, 90, 50)]
        let fill = MarketMath.fill(5, from: buys)
        #expect(fill.filled == 5)
        #expect(fill.total == 450)
    }

    @Test func fillListsSystemsOnceInOrder() {
        let sells = [sell(1, 100, 2, system: 20), sell(2, 101, 2, system: 10), sell(3, 102, 2, system: 20),
                     sell(4, 103, 2, system: 30)]
        #expect(MarketMath.fill(6, from: sells).systemIDs == [20, 10])
    }

    @Test func nearestPrefersFewerJumpsThenPrice() throws {
        let orders = [sell(1, 100, 1, system: 10), sell(2, 90, 1, system: 20), sell(3, 80, 1, system: 30), sell(4, 85, 1, system: 20)]
        let nearest = try #require(MarketMath.nearest(orders, jumps: [10: 3, 20: 1]))
        #expect(nearest.order.id == 4)
        #expect(nearest.jumps == 1)
        #expect(MarketMath.nearest(orders, jumps: [:]) == nil)
    }
}

@Suite struct HistoryTests {
    let history = [
        day("2026-09-10", average: 50),  // outside the window
        day("2026-09-15", average: 100, volume: 30),
        day("2026-10-01", average: 110, volume: 30),
        day("2026-10-14", average: 120, volume: 30),
    ]
    let asOf = MarketHistoryDay.date(fromESI: "2026-10-15")!.addingTimeInterval(3600 * 13)

    @Test func parsesESIDates() {
        let date = MarketHistoryDay.date(fromESI: "1970-01-02")
        #expect(date == Date(timeIntervalSince1970: 86_400))
        #expect(MarketHistoryDay.date(fromESI: "yesterday") == nil)
    }

    @Test func windowEndsBeforeToday() {
        let window = MarketMath.trailing(history, days: 30, asOf: asOf)
        #expect(window.map(\.average) == [100, 110, 120])
    }

    @Test func changeAcrossTheWindow() throws {
        let change = try #require(MarketMath.change(history, days: 30, asOf: asOf))
        #expect(abs(change - 0.2) < 1e-12)
    }

    @Test func averageVolumeCountsMissingDaysAsZero() {
        #expect(MarketMath.averageDailyVolume(history, days: 30, asOf: asOf) == 3)
    }

    @Test func averageVolumeOfAYoungItem() {
        let young = [day("2026-10-13", average: 1, volume: 10), day("2026-10-14", average: 1, volume: 20)]
        #expect(MarketMath.averageDailyVolume(young, days: 30, asOf: asOf) == 15)
    }

    @Test func aggregateIntoWeeks() {
        let days = (1...14).map { day(String(format: "2026-10-%02d", $0), average: Double($0), volume: 1) }
        let weeks = MarketMath.aggregate(days, bucketDays: 7)
        #expect(weeks.count == 2)
        #expect(weeks.map(\.volume) == [7, 7])
        #expect(weeks[0].average == 4)
        #expect(weeks[1].average == 11)
        #expect(weeks[0].date == MarketHistoryDay.date(fromESI: "2026-10-01"))
    }

    @Test func summary() {
        let summary = MarketSummary(orders: [sell(1, 132, 1), buy(2, 120, 1)], history: history,
                                    ccpAverage: 120, asOf: asOf)
        #expect(summary.bestSell == 132)
        #expect(summary.bestBuy == 120)
        #expect(summary.sparkline == [100, 110, 120])
        #expect(abs((summary.versusCCP ?? 0) - 0.1) < 1e-12)
        #expect(summary.sellOrderCount == 1)

        let loading = MarketSummary(orders: nil, history: nil, ccpAverage: nil)
        #expect(loading.bestSell == nil)
        #expect(loading.change == nil)
        #expect(loading.sparkline.isEmpty)
    }
}
