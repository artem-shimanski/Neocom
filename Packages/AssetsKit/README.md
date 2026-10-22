# AssetsKit

The character's assets as a tree: where everything is, what is inside which ship or container,
what a location holds, and how to find an item by name. Plain data in, plain data out.

AssetsKit deliberately has no ESI client, no SDE access and no UI. The app fetches the
records (`AssetsSheet` in `Neocom/Neocom/Model/` owns `/characters/{id}/assets` and
`/characters/{id}/assets/names`), names the root locations (`ESILookup`), reads the type rows
from the SDE, maps all of that into the structs below and builds one `AssetIndex` per fetch.
The screens under `UI/Assets/` only read the index. `AssetLocationInfo` is also
used by the contracts, industry and orders sheets to name the places they mention, and
`AssetIDRange` by the shared lookup in `ESILookup.swift`. Turning a quantity into "4 370" or a section title
into upper case is the screen's business.

## Requirements

* Swift tools 6.4, iOS 26.0+ / macOS 26.0+
* No dependencies

## Types

Input, all `Codable`, so the app can cache them as they are:

* `AssetRecord` - one record of the assets answer. `locationFlag` and `locationType` stay raw
  strings, so a flag CCP adds later is filed under a section named after it instead of being
  dropped.
* `AssetLocationInfo` - a root location as far as the app could name it (station, structure,
  structure without access, solar system, unknown). `guess(id:locationType:)` is what the
  index assumes for a root nobody named.
* `AssetIDRange` - classifies an id by `location_type` and CCP's id ranges (stations
  60,000,000..<64,000,000, systems 30,000,000..<33,000,000, ids from 10^12 may be Upwell
  structures).
* `AssetTypeInfo` - what the SDE says about a type: names, group, category, volume, capacity,
  and for ships `Slots` (slot counts, drone and fighter bay sizes); for subsystems
  `SlotModifiers`.
* `AssetSolarSystem` - name, security, region of a system.
* `AssetCategory` - the SDE ids the index needs (ship, module, charge, blueprint, container
  groups, the Asset Safety Wrap) and the order and titles of the category sections.

The index:

* `AssetIndex` - built once from the records, off the main actor; construction is linear.
  Answers: `summary`, `locations`, `regions`, `location(_:)`, `item(_:)`, `path(to:)`,
  `contents(of:)`, `fitting(ofShip:)`, `search(_:limit:)`.

Output (structured fields only):

* `AssetSummary`, `AssetLocation`, `AssetRegion` - the totals and the location list.
* `AssetSection`, `AssetRow`, `AssetCapacity` - what a location, container or ship screen
  draws: titled sections of rows, with used/total for ship racks and bays.
* `AssetPath` - a root location plus the ships and containers around an item.
* `AssetSearchResult`, `AssetSearchHit` - search hits grouped by location.
* `AssetFitting` - an assembled ship as a fit (hull, flags, quantities), ready for an
  ESI fitting.

## Rules the index encodes

* A root is any `locationID` that is not the `itemID` of another record. A record repeated
  across pages is kept once. A record caught in a cycle is never reached from a root and is
  left out of every count.
* A singleton opens (is a row of its own) if it is a ship, a container group (cargo, secure,
  audit log, freight), the Asset Safety Wrap, or anything that has children. Everything else is
  stacked by type and blueprint-copy-ness, so copies and originals never share a row.
* Ship counts sum quantities: seven packaged ships are seven, an assembled one is one.
* Loose flags (hangar, locked, unlocked, auto-fit) are sorted into category sections; any
  other flag (Deliveries, Asset Safety, ...) becomes a section named after the flag.
* A ship with known hull numbers always lists every rack and bay the hull has, empty ones
  included. Fitted subsystems add their high, medium and low slots to the hull's (a Strategic
  Cruiser has none of its own). A rack total is never below what is fitted, and charges are
  not counted as used slots.
* `fitting(ofShip:)` takes slots, drone bay and fighter bay only; fighter tubes become
  `FighterBay`, cargo and other holds are left out. Same type in the same flag is merged.
* Custom names `"None"` and empty ones are ignored. Search folds case, diacritics and width,
  needs every word to match type, group, custom, location or system name (at most 16 words), and
  returns stacks as one hit.

## Usage

```swift
import AssetsKit

let ship = AssetTypeInfo(typeID: 587, name: "Rifter", groupID: 25, groupName: "Frigate",
                         categoryID: AssetCategory.ship, categoryName: "Ship",
                         capacity: 140, slots: .init(high: 4, medium: 3, low: 3, rig: 3))
let ammo = AssetTypeInfo(typeID: 34, name: "Tritanium", groupID: 18, groupName: "Mineral",
                         categoryID: 4, categoryName: "Material", volume: 0.01)

let records = [
    AssetRecord(itemID: 1, typeID: 587, locationID: 60_003_760, locationFlag: "Hangar",
                locationType: "station", quantity: 1, isSingleton: true),
    AssetRecord(itemID: 2, typeID: 34, locationID: 60_003_760, locationFlag: "Hangar",
                locationType: "station", quantity: 5_000, isSingleton: false),
]

let index = AssetIndex(records: records,
                       locations: [60_003_760: AssetLocationInfo(id: 60_003_760, kind: .station, name: "Jita IV")],
                       types: [587: ship, 34: ammo])

for location in index.locations {
    for section in index.contents(of: location.id) {
        print(section.title, section.rows.map { "\($0.name) x\($0.quantity)" })
    }
}
let hits = index.search("trit")
let fit = index.fitting(ofShip: 1)
```

## Tests

```
cd AssetsKit && swift test
```

The tests (Swift Testing) read two JSON resources under `Tests/AssetsKitTests/Resources`: a
real first page of an assets answer and the matching SDE rows. They include a 20,000-record
build.
