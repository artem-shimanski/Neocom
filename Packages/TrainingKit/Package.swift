// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TrainingKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "TrainingKit", targets: ["TrainingKit"]),
        // The widget snapshot and the queue math over it, without SDEKit.
        .library(name: "TrainingTimeline", targets: ["TrainingTimeline"]),
    ],
    dependencies: [.package(path: "../SDE")],
    targets: [
        .target(name: "TrainingKit", dependencies: [
            "TrainingTimeline",
            .product(name: "SDEKit", package: "SDE"),
        ]),
        .target(name: "TrainingTimeline"),
        .testTarget(name: "TrainingKitTests", dependencies: ["TrainingKit"]),
        .testTarget(name: "TrainingTimelineTests", dependencies: ["TrainingTimeline"]),
    ]
)
