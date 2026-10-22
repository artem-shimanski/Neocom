// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "KillmailKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "KillmailKit", targets: ["KillmailKit"])],
    targets: [
        .target(name: "KillmailKit"),
        .testTarget(name: "KillmailKitTests", dependencies: ["KillmailKit"]),
    ]
)
