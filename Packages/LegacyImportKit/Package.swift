// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "LegacyImportKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "LegacyImportKit", targets: ["LegacyImportKit"])],
    dependencies: [.package(url: "https://github.com/artem-shimanski/DogmaKit.git", from: "0.2.1")],
    targets: [
        .target(name: "LegacyImportKit", dependencies: [.product(name: "DogmaKit", package: "DogmaKit")]),
        .testTarget(name: "LegacyImportKitTests", dependencies: ["LegacyImportKit"]),
    ]
)
