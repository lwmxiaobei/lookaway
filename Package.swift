// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDuo",
    platforms: [.macOS(.v14)],
    targets: [
        // 纯逻辑层：不依赖 AppKit / CoreMotion，可完整单测
        .target(
            name: "DuoCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MacDuo",
            dependencies: ["DuoCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DuoCoreTests",
            dependencies: ["DuoCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
