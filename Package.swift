// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BetterDictation",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BetterDictation", targets: ["BetterDictation"]),
        .executable(name: "bd-smoke", targets: ["BDSmoke"]),
    ],
    targets: [
        .target(
            name: "BetterDictationCore",
            path: "Sources/BetterDictationCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "BetterDictation",
            dependencies: ["BetterDictationCore"],
            path: "Sources/BetterDictation",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "BDSmoke",
            dependencies: ["BetterDictationCore"],
            path: "Sources/BDSmoke",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BetterDictationCoreTests",
            dependencies: ["BetterDictationCore"],
            path: "Tests/BetterDictationCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
