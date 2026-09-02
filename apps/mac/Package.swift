// swift-tools-version: 6.0
import PackageDescription

// Dependencies point one way only. See docs/05-mac-app.md.
//
//   XBotApp ── XBotOnboarding ─┐
//      │                       │
//      ├── XBotUI ── XBotCore ─┴── XBotEngine   (Foundation only)
//      │                        └─ XBotRuntime  (Foundation only)
//
// XBotEngine and XBotRuntime never import SwiftUI. That is what lets the client develop against a
// stub API while the engine runs, or does not run, somewhere else.

// Swift 6 language mode, everywhere, from the first file. This app coordinates a container runtime,
// a network client and a streaming parser; a data race between those reproduces once a fortnight and
// costs a day each time. Retrofitting strict concurrency onto a written app is much worse than
// starting inside it — the compiler's demands here produce the design we want anyway.
let strict: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "XBot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "XBot", targets: ["XBotApp"]),
    ],
    targets: [
        .target(name: "XBotEngine", swiftSettings: strict),
        .target(name: "XBotRuntime", swiftSettings: strict),
        .target(name: "XBotCore", dependencies: ["XBotEngine", "XBotRuntime"], swiftSettings: strict),
        .target(name: "XBotUI", dependencies: ["XBotCore"], swiftSettings: strict),
        .target(
            name: "XBotOnboarding",
            dependencies: ["XBotUI", "XBotEngine", "XBotRuntime"],
            swiftSettings: strict
        ),
        .executableTarget(
            name: "XBotApp",
            dependencies: ["XBotUI", "XBotCore", "XBotOnboarding", "XBotRuntime"],
            swiftSettings: strict
        ),

        .testTarget(name: "XBotEngineTests", dependencies: ["XBotEngine"], swiftSettings: strict),
        .testTarget(name: "XBotRuntimeTests", dependencies: ["XBotRuntime"], swiftSettings: strict),
        .testTarget(name: "XBotCoreTests", dependencies: ["XBotCore"], swiftSettings: strict),
    ]
)
