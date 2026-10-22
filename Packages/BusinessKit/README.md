# BusinessKit

The business math of Neocom for a character's own market orders, industry jobs and contracts:
states, progress, summaries, list orderings, and the notification moments and change detection
built on them.

Plain data in and out. BusinessKit has no ESI client, no UI and no SDE. The app maps the
generated ESI records into these `Codable` structs (and caches them on disk as they are); the
routes are owned by `OrdersSheet`, `IndustrySheet` and `ContractsSheet` in
`Neocom/Neocom/Model/`. Names of types, stations and characters, and the wording of
notifications, live in the app. Time is always a parameter (`now`, `at:`), never read inside.

## Requirements

* Swift tools 6.4 (Xcode 27); iOS 26.0+, macOS 26.0+.
* No dependencies.

## Types

Orders (`Orders.swift`)

* `CharacterOrder` - an open order (`/orders`) or a history one (`/orders/history`). `expires`
  is `issued + duration` days (for history, when it would have expired - ESI does not give the
  closing time). `outcome` adds `filled`, which ESI does not have: an expired order with
  nothing remaining traded in full.
* `OrdersSummary` - counts, ISK still to earn or spend (`price * volumeRemain`), escrow and
  orders expiring in under a day; only open orders count.
* `OrderBookPosition` - rank of an open order among its side in the region
  (`BookOrder` values, which the app maps from `MarketKit.MarketOrder`). Ties do not count as
  better, and `ownOrderIDs` are left out so you are never undercut by yourself.
* `OrderFlag`, `CharacterOrder.flag(position:now:)` - `undercut` (sell) or `outbid` (buy) when
  not first, else `expiringSoon`; with an unknown book, only the time is judged.

Industry (`Industry.swift`)

* `IndustryJob`, `IndustryActivity` - activity ids map to activities (reactions come as 9 and
  11); `runUnit` says whether `runs` counts runs, levels or copies.
* `IndustryJob.phase(at:)` - ESI keeps saying `active` after the end date, so an `active` job
  past `endDate` reads as `ready`. `progress(at:)` is 0...1: against the clock while running,
  frozen at the pause or at cancellation otherwise. `timeLeft(at:)` of a paused job is what is
  left when it resumes.
* `IndustrySummary`, `activeSortedByEnd(at:)`, `completedLatestFirst(at:)` - the strip and the
  two list orders.

Contracts (`Contracts.swift`)

* `Contract`, `ContractKind`, `ContractStatus`, `ContractAvailability` - raw ESI strings are
  stored; a value ESI adds later reads as `unknown`. `ContractStatus.tone` groups statuses as
  active, finished, closed or failed.
* Roles and groups: `roles(of:)`, `isOfferedTo`, `isForMe`. Time: `deadline` (courier:
  accepted date plus days to complete), `activeDue`, `timeLeft(at:)`, `isExpired`,
  `isOverdue` (a courier ESI still lists as in progress past its deadline), `isDueSoon`.
* `ContractsSummary`, `ContractItem` (`rawQuantity` -2 is a blueprint copy), `ContractBid`
  with `highestFirst` (earlier bid wins among equal amounts), `auctionProgress(highBid:)`.

Notifications (`Notifications.swift`)

* `IndustryReminders.plan`, `ContractReminders.plan` - the moments known in advance. Contract
  reminders fire `lead` (one hour) before the expiry of an outstanding contract or a courier
  deadline; reminders whose fire date has passed are dropped.
* `OrderWatch.check`, `ContractWatch.check` - what changed since the last background check,
  against a baseline the app keeps. Without a baseline nothing is reported, the first check
  only records. Cancelled orders and contracts are not reported (the player did that). An
  order that left the open list but is not in history yet stays in the baseline.

## Example

```swift
import Foundation
import BusinessKit

let now = Date()
let job = IndustryJob(id: 1, activityID: 1, blueprintTypeID: 1000, runs: 10,
                      startDate: now.addingTimeInterval(-3600),
                      endDate: now.addingTimeInterval(3600), status: "active")
job.phase(at: now)       // .active
job.progress(at: now)    // 0.5

let order = CharacterOrder(id: 7, typeID: 34, regionID: 10000002, locationID: 60003760,
                           isBuyOrder: false, price: 100, volumeRemain: 40, volumeTotal: 100,
                           duration: 90, issued: now)
let book = [BookOrder(id: 8, isBuyOrder: false, price: 99)]
let position = OrderBookPosition(of: order, in: book)
order.flag(position: position, now: now)   // .undercut
```

## Tests

```
cd BusinessKit
swift test
```

Swift Testing, no simulator, no other checkouts needed.
