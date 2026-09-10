// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeLimits",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClaudeLimitsCore"),
        .executableTarget(
            name: "ClaudeLimitsApp",
            dependencies: ["ClaudeLimitsCore"]
        ),
        .testTarget(
            name: "ClaudeLimitsCoreTests",
            dependencies: ["ClaudeLimitsCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
