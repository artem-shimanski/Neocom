# MarketKit

The market arithmetic of Neocom: sorting an order book, best prices and spread, filling a
quantity from the book, and the statistics of a price history (change, average daily volume,
weekly aggregation).

Plain data in and out, pure functions. MarketKit has no ESI client, no UI and no SDE. The app
maps `/markets/{region_id}/orders` and `/markets/{region_id}/history` records into
`MarketOrder` and `MarketHistoryDay` (both `Codable`, so the app caches them on disk as they
are), and the routes are owned by `Neocom/Neocom/Model/MarketSheet.swift`. Type names, region
names and distances between systems (jump counts) come from the app.

## Requirements

* Swift tools 6.4 (Xcode 27); iOS 26.0+, macOS 26.0+.
* No dependencies.

## Types

* `MarketOrder` - one order of a region's book. `range` is kept as the raw ESI string so a
  value CCP adds later neither breaks a cached file nor gets dropped. `isInStation` is true for
  ids in `stationIDs` (60,000,000...63,999,999); anything else is a player structure.
* `MarketHistoryDay` - one day of history, dated midnight UTC. `date(fromESI:)` parses ESI's
  `"2026-10-15"` strings, `nil` for anything else.
* `MarketSide` - sell (best is cheapest) or buy (best is dearest).
* `MarketMath` - the functions:
  * `sorted(_:side:)` - one side, best first; equal prices go oldest first (then by id), the
    order the game matches them in.
  * `bestSell`, `bestBuy`, `spread(bestSell:bestBuy:)` - spread is a fraction of best sell and
    goes negative when the book is crossed, which happens across stations of a region.
    `relative(_:to:)` is `value / reference - 1`.
  * `fill(_:from:)` - takes a quantity from an already sorted book and returns a `MarketFill`
    (filled, total ISK, orders used, worst price, systems touched, average price). An order
    whose `minVolume` exceeds what is still needed is skipped, as the game would refuse that
    trade. If the book runs out, `filled < requested` and `isComplete` is false.
  * `nearest(_:jumps:)` - the order fewest jumps away, cheapest among equals (dearest for buy
    orders); systems without a known distance are ignored.
  * `trailing`, `change`, `averageDailyVolume`, `aggregate` - history over a window of whole
    UTC days ending at the start of `asOf`'s day (today has no entry yet); without `asOf` the
    window ends the day after the latest entry. Days without trades are absent from ESI
    history and count as zero volume; an item younger than the window is averaged over its own
    lifetime. `aggregate(_:bucketDays:)` folds days into buckets aligned to the last day,
    dated by their first day, with a volume-weighted average and the widest low/high band.
* `MarketSummary` - the figures of the price card for one region: best prices, spread, average
  daily volume, change and sparkline over 30 days (`windowDays`), best sell against CCP's
  universe average, order counts. `orders` and `history` may be `nil` while loading; what
  depends on them is `nil` too.

## Example

```swift
import Foundation
import MarketKit

let book = [
    MarketOrder(id: 1, isBuyOrder: false, price: 105, volumeRemain: 10, locationID: 60003760, systemID: 30000142),
    MarketOrder(id: 2, isBuyOrder: false, price: 100, volumeRemain: 5, locationID: 60003760, systemID: 30000142),
    MarketOrder(id: 3, isBuyOrder: true, price: 95, volumeRemain: 50, locationID: 60003760, systemID: 30000142),
]

let sells = MarketMath.sorted(book, side: .sell)
let fill = MarketMath.fill(8, from: sells)
// fill.total == 5 * 100 + 3 * 105, fill.ordersUsed == 2, fill.isComplete

let summary = MarketSummary(orders: book, history: nil, ccpAverage: 102)
// summary.bestSell == 100, summary.spread == 0.05
```

## Tests

```
cd MarketKit
swift test
```

Swift Testing, no simulator, no other checkouts needed.
