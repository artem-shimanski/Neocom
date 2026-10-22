# Neocom

A companion app for [EVE Online](https://www.eveonline.com) for iPhone, iPad and Mac
(Mac Catalyst), written in SwiftUI. More at [getneocom.com](https://getneocom.com).

## Features

- **Pilot** — character sheet (attributes, implants, jump clones, wallet, location, ship), skills
  overview, the skill queue with a local training plan, certificates and ship mastery, several
  signed-in characters at once.
- **Fitting** — a fitting editor backed by [DogmaKit](https://github.com/artem-shimanski/DogmaKit)'s
  engine (DPS, EHP, capacitor, resistances, skills and implants of any signed-in pilot), fleets,
  the player's own fits synced through iCloud, and the character's in-game fits (list, upload).
- **Market and business** — market browser with prices and history, market orders, industry jobs,
  contracts, assets.
- **Social** — mail (read, organize, compose), killmails, zKillboard.
- **World** — planetary interaction (colonies, extractors, factories, storage), server status.
- **Database** — the full static data export browsable offline, searchable in eight languages
  (de, en, es, fr, ja, ko, ru, zh).
- **Widgets** — skill-queue widgets for the Home and Lock Screen, and training notifications.

## Requirements

- Xcode 27 (the packages use Swift tools 6.4)
- iOS / iPadOS 26.6+ (widgets 27.0+), Mac Catalyst

## Getting started

```sh
git clone https://github.com/artem-shimanski/Neocom.git
cd Neocom
```

### 1. Build the static data (once)

The app reads the EVE static data export (SDE) from SQLite files that are not in git — the
`build-sde` package plugin generates them. The wrapper does it all in one go:

```sh
Packages/SDE/Scripts/update-sde.sh        # optionally followed by language codes, e.g. en ru
```

It takes the SDE build that DogmaKit was imported from, downloads it into a shared cache
(`$EVE_SDE_CACHE`, default `~/Library/Caches/EVE-SDE`), links `Packages/SDE/.SDE` to it and runs
`build-sde`; `--check` only reports what is cached and linked. To do the same by hand, the plugin
needs the SDE dump in JSONL format:

1. Download the JSONL build from [developers.eveonline.com/static-data](https://developers.eveonline.com/static-data)
   and unpack it into `Packages/SDE/.SDE` (the folder must contain `_sde.jsonl`).
   A different location can be set in `Packages/SDE/.sde-config.json` (`"sde"`) or passed with `--sde <path>`.
2. Optionally put the PNG market-group icons into `Packages/SDE/.icons/items`; without them the
   build only prints a warning.
3. Run the plugin:

```sh
cd Packages/SDE
swift package --allow-writing-to-package-directory build-sde
```

In Xcode the same is available from the context menu of the `SDE` package (*BuildSDE*). Pass
language codes to build a subset, which is much faster while developing:
`... build-sde en ru`. The plugin writes `sde.sqlite` and one `text-<lang>.sqlite` per language
into `Packages/SDE/Sources/SDEData*/Data`. Without them the app traps on launch.

If `swift` on your `PATH` is older than 6.4, run it through the Xcode 27 toolchain
(`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift ...`).

### 2. Open and build

Open `Neocom.xcworkspace` and run the `Neocom` scheme. The GitHub packages ship Swift macros and
the SDE package a build-tool plugin, so Xcode asks to trust them on first build. The plugin fails
the build when the databases come from a different SDE build than DogmaKit. From the command line:

```sh
xcodebuild -workspace Neocom.xcworkspace -scheme Neocom \
  -destination 'generic/platform=iOS Simulator' -skipMacroValidation -skipPackagePluginValidation build
```

Signing in with EVE SSO works out of the box only for the official build — see below for
running your own copy.

## Building your own copy

The bundled identifiers belong to the official App Store build. To run a fork you need your own:

1. **EVE SSO application.** Create one at [developers.eveonline.com](https://developers.eveonline.com)
   with *Authentication & API Access*, callback URL `eveauth-neocom://sso`, and the scopes listed in
   `SSOConfiguration.scopes`. Put its Client ID into `SSOConfiguration.clientID`
   (`Neocom/Neocom/Services/SSO/SSOConfiguration.swift`). The app is a public client:
   authorization code flow with PKCE, no secret. If you change the callback, change
   `SSOConfiguration.callbackURL` to match.
2. **Bundle identifiers.** `com.shimanski.neocom` (app) and `com.shimanski.neocom.widgets`
   (widget extension), in the Xcode project.
3. **Team.** Set `DEVELOPMENT_TEAM` (project signing settings) to your own team.
4. **App Group.** `group.com.shimanski.neocom` in `Neocom/Neocom.entitlements` and
   `Neocom/NeocomWidgets.entitlements`; the app and the widgets share the skill-queue snapshot
   through it.
5. **iCloud.** The container `iCloud.com.shimanski.neocom` in `Neocom/Neocom.entitlements`
   (CloudKit sync of the player's fits).
6. **Tip jar.** Product IDs in `Neocom/Neocom/Services/Store/TipConfiguration.swift` and
   `Neocom/Tips.storekit` (also its `appStoreID`), or remove the Support screen.
7. **ESI User-Agent.** CCP asks for a descriptive one with contact details — edit
   `ESIService.userAgent` in `Neocom/Neocom/Services/ESI/ESIService.swift`.

Changing `SSOConfiguration.scopes` invalidates stored refresh tokens: characters have to sign in
again.

## Project layout

```
Neocom/
  Neocom/            the app: App, Model, Services, Support, UI (one folder per section, UI/HUD is the design system)
  NeocomWidgets/     widget extension; reads only the snapshot the app writes into the App Group
  Shared/            code compiled into both the app and the extension
  Tips.storekit      StoreKit configuration for the tip jar
Packages/
  TrainingKit        training-time math, skill queue and plan, certificates; TrainingTimeline is its SDE-free product for widgets
  MarketKit          market math: orders, history, summaries, quantity fill
  BusinessKit        the character's own orders, industry jobs and contracts
  AssetsKit          asset trees and locations
  MailKit            mail model and helpers
  KillmailKit        killmail model and helpers
  LegacyImportKit    import of fits from the earlier Neocom
  SDE                SDEKit (typed access to the static data), the importer and the build-sde plugin
site/                the landing site (getneocom.com), plain static HTML
```

The packages are plain Swift: data in, data out, no UI and no networking.

Open-source dependencies (Swift Package Manager):

- [EveAPIKit](https://github.com/artem-shimanski/EveAPIKit) — ESI client (`ESIKit`) and zKillboard client (`ZKillKit`)
- [LiteRow](https://github.com/artem-shimanski/LiteRow) — the SQLite layer under SDE, with a SwiftUI bridge
- [DogmaKit](https://github.com/artem-shimanski/DogmaKit) — the fitting engine

Data pulled from the server is cached on disk as plain JSON; what the player creates (training
plan, fits) lives in SwiftData. Accounts and refresh tokens are kept in the keychain.

## Tests

Each package has its own tests; run them from the package directory:

```sh
cd Packages/TrainingKit
swift test
```

`SDE` tests need the built databases (see above).

## License

[MIT](LICENSE) © 2026 Artem Shimanski.

## Legal

EVE Online, the EVE logo, EVE and all associated logos and designs are the intellectual property
of CCP hf. All artwork, screenshots, characters, vehicles, storylines, world facts or other
recognizable features of the intellectual property relating to these trademarks are likewise the
intellectual property of CCP hf. EVE Online and the EVE logo are the registered trademarks of
CCP hf. All rights are reserved worldwide. All other trademarks are the property of their
respective owners. Neocom is an independent project: it is not affiliated with and is not
endorsed by CCP hf. CCP is in no way responsible for the content on or functioning of this
program, nor for any damage it may cause, and is not liable for any inaccuracies in it.

The static data export, item images and icons are the property of CCP Games and are used under
the [EVE Online developer license](https://developers.eveonline.com/license-agreement).

Bugs and ideas: [GitHub Issues](https://github.com/artem-shimanski/Neocom/issues).
