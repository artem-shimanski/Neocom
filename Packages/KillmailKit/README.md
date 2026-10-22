# KillmailKit

Killmails and zKillboard searches as plain data and the math over them: kill or loss from
a pilot's side, ranked attackers and damage shares, the lost items by section, an ISK estimate,
the lost fit, paging of the recent list, and the criteria of a zKillboard search turned into
query parameters.

KillmailKit deliberately has no ESI client, no zKillboard client and no UI. The app fetches
and caches: `KillmailsSheet` (`Neocom/Neocom/Model/`) owns
`/characters/{id}/killmails/recent` and `/killmails/{id}/{hash}`, `ZKillboardSheet` owns every
zKillboard call. They map the generated records into `Killmail` and the criteria's
`KillboardQueryParameters` into their own query. The screens (`UI/Killmails/`, `UI/ZKillboard/`)
read the types here; `Services/Fitting/Killmail+Dogma.swift` feeds `fitItems` to the fitting
tool, and the mail screens use `KillmailRef` to open a `killReport:` link. Names, prices and
the SDE (ship groups, whether a type is a charge) are passed in by the caller as closures.

## Requirements

* Swift tools 6.4, iOS 26.0+ / macOS 26.0+
* No dependencies

## Types

The killmail (`Killmail.swift`), all `Codable`:

* `KillmailRef` - id and hash, which together open a killmail on the public endpoint.
* `Killmail`, `KillmailVictim`, `KillmailAttacker`, `KillmailItem` - one killmail as plain
  data. Killmails never change once written, so they can be cached forever.
* `KillmailSide` - `kill` or `loss`; `Killmail.side(for:)` is a loss when the pilot is the
  victim.

Attackers (`KillmailAttackers.swift`): `rankedAttackers`, `leadingAttackers`, `finalBlow`,
`damageShare(of:)`, `attackerSummary` (`KillmailAttackerSummary`).

Items and value (`KillmailItems.swift`):

* `KillmailSection` - the inventory flag ranges (high 27-34, medium 19-26, low 11-18, rigs
  92-99, subsystems 125-132, service 164-171, drone bay 87, fighter bay 158, cargo 5,
  implants 89, everything else "other").
* `itemGroups(isCharge:)` - `KillmailItemGroup`s of `KillmailItemRow`s, nested rows for loaded
  charges and container contents.
* `value(price:)`, `KillmailValue` - destroyed and dropped worth at average prices.
* `fitItems`, `fittingFlag(_:)`, `KillmailFitItem` - the lost fit with ESI fitting flag names.

The recent list (`KillmailList.swift`): `KillmailRecentList` (paging and refresh),
`KillmailFilter` (all/kills/losses), `KillmailListStats`, `KillmailDay`.

zKillboard (`Killboard.swift`): `KillboardSubject`/`KillboardSubjectKind`,
`KillboardCriteria` and its option enums, `KillboardQueryParameters`, `KillboardEntry`,
`KillboardResults` (paging), `KillboardDay`, and `KillboardKillmailID.parse(_:)`, which reads
a bare id or a zKillboard link.

## Rules the code encodes

* `totalDamage` is `damage_taken`, or the attackers' sum when ESI says 0. Shares are clamped
  to 0...1. Ranking: damage, then final blow, then pilots before NPCs, then ESI's order. An
  attacker without a character is an NPC. A weapon equal to the ship type is not a weapon.
* In a slot rack ESI gives a module and its charge the same flag. With an `isCharge`
  predicate the first non-charge is the module; without one, the first single item is.
* A blueprint copy (`singleton == 2`) is worth nothing. A hull counts as destroyed. A
  stack can be partly destroyed and partly dropped.
* `fitItems` is empty for a capsule (670, 33328), skips cargo, implants and containers'
  contents, and joins split stacks.
* Days are UTC days (EVE time).
* The recent list is unique by id, newest first. `refreshed` keeps older pages only while
  page 1 still joins up with them; otherwise paging starts over.
* A subject that is a place has no side: kills/losses and final blow are dropped from the
  query. A minimum value is rounded down to a multiple of 500M. Pages are 1...100, 200
  entries each; a short page is the last. `pastSeconds` and a calendar month are exclusive.

## Usage

```swift
import KillmailKit

let victim = KillmailVictim(characterID: 1, shipTypeID: 587, damageTaken: 900,
                            items: [KillmailItem(typeID: 2488, flag: 27, destroyed: 1)])
let attacker = KillmailAttacker(characterID: 2, damageDone: 900, isFinalBlow: true)
let killmail = Killmail(id: 100, hash: "abc", time: .now, solarSystemID: 30000142,
                        victim: victim, attackers: [attacker])

killmail.side(for: 2)                                  // .kill
killmail.rankedAttackers.first?.share                  // 1.0
killmail.value(price: { $0 == 587 ? 1_000_000 : nil }).total
let fit = killmail.fitItems                            // HiSlot0

var criteria = KillboardCriteria(subject: KillboardSubject(kind: .character, id: 2, name: "Pilot"))
criteria.side = .losses
criteria.period = .pastWeek
let query = criteria.parameters(page: 1)               // KillboardQueryParameters?

KillboardKillmailID.parse("https://zkillboard.com/kill/139208025/")  // 139208025
```

## Tests

```
cd KillmailKit && swift test
```

Swift Testing, no resources, no network.
