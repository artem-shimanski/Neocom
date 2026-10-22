// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MarketKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "MarketKit", targets: ["MarketKit"])],
    targets: [
        .target(name: "MarketKit"),
        .testTarget(name: "MarketKitTests", dependencies: ["MarketKit"]),
    ]
)
