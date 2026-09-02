// swift-tools-version: 6.0
import PackageDescription

// Dependencies point one way only. See docs/05-mac-app.md.
//
//   XBotApp ── XBotOnboarding ─┐
//      │                       │
//      ├── XBotUI ── XBotCore ─┴── XBotEngine   (Foundation only)
//      │                        └─ XBotRuntime  (Foundation only)
//
// XBotEngine and XBotRuntime never import SwiftUI. That is what lets the
// client develop against a stub API while the engine fork is in flight.

let package = Package(
    name: "XBot",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "XBotApp", targets: ["XBotApp"]),
    ],
    targets: [
        .target(name: "XBotEngine"),
        .target(name: "XBotRuntime"),
        .target(name: "XBotCore", dependencies: ["XBotEngine", "XBotRuntime"]),
        .target(name: "XBotUI", dependencies: ["XBotCore"]),
        .target(name: "XBotOnboarding", dependencies: ["XBotUI", "XBotEngine", "XBotRuntime"]),
        .target(name: "XBotApp", dependencies: ["XBotUI", "XBotCore", "XBotOnboarding"]),

        .testTarget(name: "XBotEngineTests", dependencies: ["XBotEngine"]),
        .testTarget(name: "XBotRuntimeTests", dependencies: ["XBotRuntime"]),
        .testTarget(name: "XBotCoreTests", dependencies: ["XBotCore"]),
    ]
)
