// swift-tools-version: 6.4

import PackageDescription
import CompilerPluginSupport

// Matches the importer's `Language` and `BuildSDEPlugin.languages`; one target with a single file
// per language.
let languages = ["de", "en", "es", "fr", "ja", "ko", "ru", "zh"]

func dataTarget(_ name: String) -> Target {
    // The resource is the `Data` directory: the `build-sde` plugin puts the file there, so it is
    // absent before the first build. The name `Resources` is not allowed: `codesign` treats such a
    // folder at the bundle root as the legacy bundle format and refuses to sign it.
    .target(
        name: name,
        resources: [.copy("Data")],
        // The main database must match the SDE build DogmaKit was imported from.
        plugins: name == "SDEDataMain" ? ["CheckSDEVersion"] : []
    )
}

func dataProduct(_ name: String) -> Product {
    .library(name: name, targets: [name])
}

let dataTargetNames: [String] = ["SDEDataMain"] + languages.map { "SDEData\($0.uppercased())" }

let package = Package(
    name: "SDE",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(
            name: "SDEKit",
            targets: ["SDEKit"]
        ),
        // The plugin is also visible in the context menu when SDE is a dependency.
        .plugin(
            name: "BuildSDE",
            targets: ["BuildSDE"]
        ),
    // Database files: the structure and the languages as separate products.
    ] + dataTargetNames.map(dataProduct),
    dependencies: [
        .package(url: "https://github.com/artem-shimanski/LiteRow.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/artem-shimanski/DogmaKit.git", from: "0.2.1")
    ],

    targets: [
        .target(
            name: "SDEKit",
            dependencies: [
                "SDEModels",
                .product(name: "LiteRow", package: "LiteRow")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "SDEModels",
            dependencies: [
                .product(name: "LiteRow", package: "LiteRow"),
                .product(name: "DogmaIDs", package: "DogmaKit")
            ]
        ),
        .executableTarget(
            name: "SDEDataImporter",
            dependencies: [
                "SDEModels",
                .product(name: "LiteRowBuild", package: "LiteRow"),
                // The module slot is asked from the engine (`TypeCatalog.slot(of:)`): the engine
                // must accept everything the UI offers to fit.
                .product(name: "DogmaKit", package: "DogmaKit")
            ]
        ),
        // Full build of the database files from the dump, placed into the resource targets.
        .plugin(
            name: "BuildSDE",
            capability: .command(
                intent: .custom(
                    verb: "build-sde",
                    description: "Собирает базу SDE и раскладывает файлы по таргетам SDEData*"
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "готовые файлы базы кладутся в Sources/SDEData*/Data"
                    )
                ]
            ),
            dependencies: ["SDEDataImporter"]
        ),
        .executableTarget(
            name: "SDEVersionCheck",
            dependencies: [.product(name: "DogmaIDs", package: "DogmaKit")]
        ),
        .plugin(
            name: "CheckSDEVersion",
            capability: .buildTool(),
            dependencies: ["SDEVersionCheck"]
        ),
        // Tests build the database themselves and do not depend on `.SDE` or prebuilt files.
        .testTarget(
            name: "SDETests",
            dependencies: [
                "SDEKit",
                "SDEModels",
                "SDEDataImporter",
                .product(name: "LiteRow", package: "LiteRow"),
                .product(name: "LiteRowBuild", package: "LiteRow")
            ]
        )
    // Resource targets: one database file each.
    ] + dataTargetNames.map(dataTarget)
)
