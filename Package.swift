// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LookAway",
    platforms: [.macOS(.v14)],
    targets: [
        // 纯逻辑层：不依赖 AppKit / CoreMotion，可完整单测
        .target(
            name: "LookAwayCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "LookAway",
            dependencies: ["LookAwayCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LookAwayCoreTests",
            dependencies: ["LookAwayCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
