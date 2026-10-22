// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "BusinessKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "BusinessKit", targets: ["BusinessKit"])],
    targets: [
        .target(name: "BusinessKit"),
        .testTarget(name: "BusinessKitTests", dependencies: ["BusinessKit"]),
    ]
)
