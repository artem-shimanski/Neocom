# TrainingKit

The training-time math of Neocom: skill points, training time, the training plan, a pilot's
standing in each skill, certificates and ship mastery, and the notification moments of the
skill queue.

Plain data in and out. TrainingKit has no ESI client, no UI and no SQL; it does not read the
SDE database. The app loads `SkillCatalog` and `CertificateCatalog` out of the SDE
(`Neocom/Neocom/Services/SDE/CertificateBrowser.swift` for certificates), maps ESI responses
into `CharacterSnapshot`, and hands them over. Names, groups and sorting stay in the app. Every
function is a pure lookup or calculation, so the tests need neither a database nor a simulator.

## Requirements

* Swift tools 6.4 (Xcode 27); iOS 26.0+, macOS 26.0+.
* Depends on `SDEKit` from the SDE package at `../SDE` (`Packages/SDE`). It is used for the typed ids
  (`TypeID`, `GroupID`, `CertificateID`) and `CharacterAttribute`.

## Types

Reference data

* `SkillCatalog` - skills (rank, primary and secondary attribute, prerequisites) and the
  attribute bonus of each implant type. `expand(_:)` expands requirements depth-first,
  prerequisites first, duplicates collapsed to the highest level; it is cycle-safe.
  Unknown types pass through without prerequisites.
* `CertificateCatalog`, `Certificate` - which skills a certificate asks for at each grade.
  `requirements(of:tier:)` takes one certificate or a set (a ship's mastery level; a skill
  shared by several certificates appears once, at its highest level). `tier(of:trainedLevel:)`
  returns the highest grade reached, or `nil` below basic.
* `CertificateTier` - the five grades. `rawValue` is the SDE's 0...4; `displayNumber` is what
  the game shows (1...5) and is the one that reaches the screen. The same scale is the ship
  mastery level.

The character

* `CharacterAttributes` - the five attributes; `.starting` is a placeholder shown before ESI
  answers.
* `CharacterSnapshot` - character data as ESI hands it over, `Codable` so it can sit in the ESI
  disk cache.
* `Pilot` - a snapshot with three corrections applied in `init` and nowhere else: implant
  bonuses added to the base attributes; queue entries already finished get their level
  credited (`/skills` lags behind); the entry in training gets its partial skill points. Its
  `queue` is the future of the queue only. Credits never lower a level or points that `/skills`
  already reports.

Calculations

* `TrainingMath` - `skillPoints(rank:level:)` is `250 * rank * 2^(2.5 * (level - 1))`, rounded;
  `level(rank:skillPoints:)` is its inverse; `skillPointsPerSecond` is
  `(primary + secondary / 2) / 60`; `trainingTime` returns 0 instead of dividing by zero.
* `TrainingQueue` - the plan. The unit is one level of one skill (`Item`). Adding a skill adds
  its missing prerequisites too. Levels the pilot already has are skipped; a (skill, level)
  pair is never planned twice; a first level starts from the points the pilot already holds;
  skills missing from the catalog are dropped rather than shown as zero time. `remove(_:)`
  drops the level and everything above it in that skill.
* `SkillStanding`, `SkillTally` - the state of one skill for a pilot (`trainedToV`, `canTrain`,
  `needsBook`, `locked`), the five level marks (trained, training, queued, planned, empty) and
  the counts per group on the Skills screen. The local plan comes in as a planned level.
* `TrainingReminders` - `plan(...)` turns the queue into local-notification moments
  ("skill trained", "queue ending" with a lead in hours). Entries without a finish date (a
  paused queue) and moments already past are left out. `state(of:now:)` reports empty, paused
  or training until a date.

## Example

```swift
import SDEKit
import TrainingKit

let skill = TypeID(rawValue: 3300)
let catalog = SkillCatalog(
    skills: [skill: .init(rank: 1, primaryAttribute: .intelligence, secondaryAttribute: .memory)],
    implantBonuses: [:]
)
let snapshot = CharacterSnapshot(attributes: .starting, implants: [], skills: [],
                                 queue: [], totalSkillPoints: 0)

let pilot = Pilot(snapshot: snapshot, catalog: catalog)
var plan = TrainingQueue(pilot: pilot, catalog: catalog)
plan.add(skill: skill, level: 3)
print(plan.items.count, plan.totalTime)   // 3 levels, seconds
```

## Tests

```
cd TrainingKit
swift test
```

Swift Testing, no simulator. The package resolves `SDEKit` from `../SDE`, so that package
must exist; the tests use hand-built catalogs and do not touch the SDE sqlite files, so
`build-sde` is not needed for them.
