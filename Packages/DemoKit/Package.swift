// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "DemoKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DemoKit", targets: ["DemoKit"]),
        .library(name: "DemoFixtures", targets: ["DemoFixtures"]),
        .executable(name: "demo-fixtures", targets: ["demo-fixtures"]),
    ],
    dependencies: [
        .package(url: "https://github.com/artem-shimanski/EveAPIKit.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.13.2"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.8.0"),
    ],
    targets: [
        .target(name: "DemoFixtures"),
        .target(
            name: "DemoKit",
            dependencies: [
                "DemoFixtures",
                .product(name: "ESIKit", package: "EveAPIKit"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]
        ),
        .target(name: "DemoExport", dependencies: ["DemoFixtures"]),
        .executableTarget(name: "demo-fixtures", dependencies: ["DemoExport"]),
        .testTarget(name: "DemoFixturesTests", dependencies: ["DemoFixtures", "DemoExport"]),
        .testTarget(
            name: "DemoKitTests",
            dependencies: [
                "DemoKit",
                "DemoExport",
                .product(name: "ESIKit", package: "EveAPIKit"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]
        ),
    ]
)
