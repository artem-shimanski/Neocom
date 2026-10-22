// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "AssetsKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "AssetsKit", targets: ["AssetsKit"])],
    targets: [
        .target(name: "AssetsKit"),
        .testTarget(name: "AssetsKitTests",
                    dependencies: ["AssetsKit"],
                    resources: [.copy("Resources")]),
    ]
)
