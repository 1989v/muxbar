// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "muxbar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "muxbar", targets: ["MuxBarApp"]),
        .library(name: "TmuxKit", targets: ["TmuxKit"]),
        .library(name: "Core", targets: ["Core"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "MuxBarApp",
            dependencies: ["Core", "TmuxKit", .product(name: "Logging", package: "swift-log")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "Core",
            dependencies: [.product(name: "Logging", package: "swift-log")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "TmuxKit",
            dependencies: ["Core", .product(name: "Logging", package: "swift-log")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "TmuxKitTests", dependencies: ["TmuxKit"]),
        .testTarget(name: "TmuxKitIntegrationTests", dependencies: ["TmuxKit"]),
    ]
)
