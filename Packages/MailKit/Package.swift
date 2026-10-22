// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MailKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "MailKit", targets: ["MailKit"])],
    targets: [
        .target(name: "MailKit"),
        .testTarget(name: "MailKitTests", dependencies: ["MailKit"]),
    ]
)
