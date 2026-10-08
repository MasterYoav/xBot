// swift-tools-version: 6.2
import PackageDescription

// Dependencies point one way only:
//
//   XBotApp ── XBotUI ── XBotCore ── XBotBrain   (Foundation only)
//
// XBotBrain never imports SwiftUI. It spawns agent CLIs and parses what they print, and it is tested
// against recorded output without a window.

// Swift 6 language mode, everywhere. This app runs child processes, a database and a UI at once.
let strict: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "XBot",
    // macOS 26: Apple's Containerization framework, which gives a bot its own machine, needs it.
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "XBot", targets: ["XBotApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "XBotBrain", swiftSettings: strict),
        .target(name: "XBotCore", dependencies: ["XBotBrain"], swiftSettings: strict),
        .target(
            name: "XBotUI",
            dependencies: ["XBotCore"],
            resources: [.copy("Resources/xBot.icns"), .copy("Resources/sunset.jpg")],
            swiftSettings: strict
        ),
        .executableTarget(
            name: "XBotApp",
            dependencies: [
                "XBotUI",
                "XBotCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .copy("Resources/Assets.car"),
                .copy("Resources/xBot.icns"),
            ],
            swiftSettings: strict
        ),

        .testTarget(
            name: "XBotBrainTests",
            dependencies: ["XBotBrain"],
            resources: [.copy("Fixtures")],
            swiftSettings: strict
        ),
        .testTarget(name: "XBotCoreTests", dependencies: ["XBotCore"], swiftSettings: strict),
        .testTarget(name: "XBotUITests", dependencies: ["XBotUI"], swiftSettings: strict),
    ]
)
