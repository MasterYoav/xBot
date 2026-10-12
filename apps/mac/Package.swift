// swift-tools-version: 6.2
import PackageDescription

// Dependencies point one way only:
//
//   XBotApp ── XBotUI ── XBotCore ── XBotBrain   (Foundation only)
//                           ├────── XBotRemote  (Foundation + Network; also builds for iOS)
//                           └────── XBotWorld   (SwiftUI pixel art: avatars and worlds; also builds for iOS)
//
// XBotBrain never imports SwiftUI. It spawns agent CLIs and parses what they print, and it is tested
// against recorded output without a window.

// Swift 6 language mode, everywhere. This app runs child processes, a database and a UI at once.
let strict: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "XBot",
    // macOS 26: Apple's Containerization framework, which gives a bot its own machine, needs it.
    // iOS 26: only XBotRemote (the wire to the iPhone/iPad app) builds for it.
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .executable(name: "XBot", targets: ["XBotApp"]),
        .library(name: "XBotRemote", targets: ["XBotRemote"]),
        .library(name: "XBotWorld", targets: ["XBotWorld"]),
        .library(name: "XBotMarkdown", targets: ["XBotMarkdown"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // The in-app terminal: a full VT emulator (vim, htop and the agents' own TUIs work in it).
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", .upToNextMinor(from: "1.20.0")),
    ],
    targets: [
        .target(name: "XBotBrain", swiftSettings: strict),
        // The wire between the Mac and the iPhone/iPad app. Foundation and Network only.
        .target(name: "XBotRemote", swiftSettings: strict),
        // The crew's looks and their pixel worlds: SwiftUI only, shared with the iPhone/iPad app.
        .target(name: "XBotWorld", swiftSettings: strict),
        // Markdown files as editable blocks, written back as Markdown (Foundation only; for the phone).
        .target(name: "XBotMarkdown", swiftSettings: strict),
        .target(name: "XBotCore", dependencies: ["XBotBrain", "XBotRemote", "XBotWorld", .product(name: "SwiftTerm", package: "SwiftTerm")],
                swiftSettings: strict),
        .target(
            name: "XBotUI",
            dependencies: ["XBotCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            resources: [.copy("Resources/xBot.icns"), .copy("Resources/sunset.jpg"), .copy("Resources/AppIcons")],
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
        .testTarget(
            name: "XBotCoreTests", dependencies: ["XBotCore"], resources: [.copy("Fixtures")], swiftSettings: strict
        ),
        .testTarget(name: "XBotMarkdownTests", dependencies: ["XBotMarkdown"], swiftSettings: strict),
        .testTarget(name: "XBotRemoteTests", dependencies: ["XBotRemote"], swiftSettings: strict),
        .testTarget(name: "XBotUITests", dependencies: ["XBotUI"], swiftSettings: strict),
    ]
)
