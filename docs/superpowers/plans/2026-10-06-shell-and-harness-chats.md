# Shell and Harness Chats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Docker/OpenBot app with a native shell where a person adds folders as projects and chats with Claude Code or Codex inside them, with every chat saved locally.

**Architecture:** Three library modules and the app. `XBotBrain` (Foundation only) spawns an installed agent CLI per turn, feeds the prompt on stdin and turns its JSON-lines stream into `BrainEvent`s. `XBotCore` keeps projects, chats and messages in SQLite and owns the `@MainActor @Observable Workspace` that runs turns. `XBotUI` renders a sidebar, chat tabs, a transcript and a composer. The old engine, runtime, onboarding and their tests are deleted first, because they collide with the new types and nothing in the new app uses them.

**Tech Stack:** Swift 6.2 tools / Swift 6 language mode, SwiftUI + Observation, system `SQLite3`, Foundation `Process`, Swift Testing, Sparkle (kept).

**Spec:** `docs/superpowers/specs/2026-10-06-xbot-redesign-design.md` — this plan is sub-project 1, part a. Checkpoints, worktrees, split panes and the Changes inspector are part b, the next plan.

## Global Constraints

- Platform floor: **macOS 26, Apple silicon** — `platforms: [.macOS(.v26)]`, `swift-tools-version: 6.2`.
- Swift 6 language mode on every target (`.swiftLanguageMode(.v6)`), `@Observable`, `@MainActor` on view models.
- No new third-party dependencies. Sparkle is the only one.
- Every user-visible string goes through `String(localized:)`; CLI product names ("Claude Code", "Codex") are names, not copy.
- Design tokens only in views: `Palette`, `Space`, `Radius`, `Metrics`, `Typography`, `Motion`. No raw hex, point sizes or durations.
- No user-facing text tells anyone to run, open Terminal, edit or paste.
- Keys never leave the Keychain (nothing in this plan stores a key).
- No listening ports. Nothing in this plan opens one.
- Do not edit `README.md` (standing instruction from the user).
- Verification: `scripts/generate-app-icon.sh` once on a fresh clone, then `cd apps/mac && swift build --build-tests && swift test`.

## Review Focus

1. **A prompt that begins with `-` or is very long** must reach the CLI intact — it goes on stdin, never argv (Task 4 test `promptTravelsOnStdinEvenWhenItLooksLikeAFlag`).
2. **A CLI that exits or is killed without a final event** must end the turn with a visible failure, never an endless spinner (Task 4 test `exitWithoutAResultIsAFailure`).
3. **A project folder deleted or moved since it was added** must fail the turn with a sentence naming the folder, not spawn in a missing directory (Task 4 test `missingFolderFailsWithoutSpawning`).
4. **Sending while a reply is still running** must be refused with the typed text kept in the composer (Task 7 test `sendingWhileRunningIsRefused`; composer only clears on success).
5. **Stopping mid-reply or quitting** must keep what had arrived and mark it stopped (Task 7 test `stopKeepsThePartialReply`).

---

### Task 1: Clean slate and the new package

**Files:**
- Delete: `apps/mac/Sources/XBotEngine/`, `apps/mac/Sources/XBotRuntime/`, `apps/mac/Sources/XBotOnboarding/`, `apps/mac/Tests/XBotEngineTests/`, `apps/mac/Tests/XBotRuntimeTests/`, `apps/mac/Tests/XBotOnboardingTests/`
- Delete from `apps/mac/Sources/XBotCore/`: everything except `MessageMarkdown.swift`, `CodeHighlight.swift`, `KeychainSecretStore.swift`, `AppUpdateControlling.swift`, `AppUpdateTrust.swift`
- Delete from `apps/mac/Sources/XBotUI/`: everything except `DesignSystem/`, `Components/CodeBlockView.swift`, `Components/AppMark.swift`, `AboutPanel.swift`, `Resources/`
- Delete from `apps/mac/Sources/XBotApp/`: `AppShellView.swift`, `QuitHandler.swift`, `Resources/engine-manifest-fallback.json`
- Delete tests that cover deleted code: every file in `Tests/XBotCoreTests/` except `MessageMarkdownTests.swift`, `CodeHighlightTests.swift`, `AppUpdateTests.swift`, `AppUpdateTrustTests.swift`; `Tests/XBotUITests/AdminWebViewTests.swift`, `Tests/XBotUITests/MessageBubbleRenderTests.swift`
- Rewrite: `apps/mac/Package.swift`, `apps/mac/Sources/XBotApp/XBotApp.swift`
- Modify: `apps/mac/Resources/Info.plist` (`LSMinimumSystemVersion` → `26.0`)
- Create: `apps/mac/Sources/XBotBrain/BrainEvent.swift` (placeholder module so the target exists; filled in Task 2)

**Interfaces:**
- Produces: targets `XBotBrain`, `XBotCore`, `XBotUI`, `XBotApp`; test targets `XBotBrainTests`, `XBotCoreTests`, `XBotUITests`.

- [ ] **Step 1: Delete the old modules and their tests** (commands above via `git rm -r`). If a kept file fails to compile because it referenced a deleted type, delete the reference, not the kept file. `AppUpdateTests.swift` stays only if it compiles against the kept files alone; otherwise delete it.

- [ ] **Step 2: Write `Package.swift`**

```swift
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
            resources: [.copy("Resources/xBot.icns")],
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
```

- [ ] **Step 3: Minimal `XBotApp.swift`** so the package builds; Task 8 replaces the window content.

```swift
import AppKit
import SwiftUI
import XBotCore
import XBotUI

@main
struct XBotApp: App {
    private let appUpdates = SparkleAppUpdateController()

    var body: some Scene {
        Window("xBot", id: "main") {
            Text(verbatim: "xBot")
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "About xBot")) { AboutPanel.show() }
            }
            CommandGroup(after: .appInfo) {
                Button(String(localized: "Check for Updates…")) {
                    appUpdates.checkForUpdates(userInitiated: true)
                }
            }
            CommandGroup(replacing: .help) {
                Button(String(localized: "xBot Documentation")) {
                    NSWorkspace.shared.open(AboutPanel.documentationURL)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Placeholder `XBotBrain/BrainEvent.swift`** containing `import Foundation` only, and an empty `Tests/XBotBrainTests/Fixtures/.keep`.

- [ ] **Step 5: Build and test**

Run: `cd apps/mac && swift build --build-tests && swift test`
Expected: builds; the kept suites (markdown, code highlight, update trust, About credits) pass.

- [ ] **Step 6: Commit** — `git commit -m "Delete the Docker engine client, runtime and onboarding; macOS 26 package."`

---

### Task 2: Brain events and the Claude Code stream

**Files:**
- Modify: `apps/mac/Sources/XBotBrain/BrainEvent.swift`
- Create: `apps/mac/Sources/XBotBrain/HarnessKind.swift`, `apps/mac/Sources/XBotBrain/ClaudeStream.swift`, `apps/mac/Sources/XBotBrain/JSONLine.swift`
- Create: `apps/mac/Tests/XBotBrainTests/Fixtures/claude-tool-turn.jsonl`, `apps/mac/Tests/XBotBrainTests/Fixtures/claude-partial-turn.jsonl`
- Test: `apps/mac/Tests/XBotBrainTests/ClaudeStreamTests.swift`

**Interfaces:**
- Produces:
  - `enum BrainEvent: Equatable, Sendable { case session(String), textDelta(String), text(String), toolCall(id: String, name: String, summary: String), toolResult(id: String, output: String, isError: Bool), notice(String), done, failed(String) }` with `var isTerminal: Bool`
  - `enum PermissionMode: String, Codable, CaseIterable, Sendable { case readOnly, editFiles, fullAccess }`
  - `struct TurnRequest: Equatable, Sendable { prompt: String; directory: URL; model: String?; mode: PermissionMode; resumeID: String? }`
  - `protocol Brain: Sendable { func run(_ request: TurnRequest) -> AsyncStream<BrainEvent> }`
  - `enum HarnessKind: String, Codable, CaseIterable, Sendable { case claude, codex }` with `displayName`, `executableName`, `models: [String?]`, `arguments(for:) -> [String]`, `events(from line: String) -> [BrainEvent]`

- [ ] **Step 1: Record the fixtures.** Taken from a real `claude -p … --output-format stream-json --verbose` run, with `hook_*` system lines removed and the `init` line cut to the fields we read:

`claude-tool-turn.jsonl`
```jsonl
{"type":"system","subtype":"init","cwd":"/private/tmp/work","session_id":"a5984ed8-b509-4f00-9d68-025be0f5f129"}
{"type":"assistant","message":{"model":"claude-opus-5-5","id":"msg_1","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_01","name":"Read","input":{"file_path":"/private/tmp/work/a.txt"}}]},"parent_tool_use_id":null,"session_id":"a5984ed8-b509-4f00-9d68-025be0f5f129"}
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":"1\thello\n2\t"}]},"parent_tool_use_id":null,"session_id":"a5984ed8-b509-4f00-9d68-025be0f5f129"}
{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}
{"type":"assistant","message":{"model":"claude-opus-5-5","id":"msg_2","type":"message","role":"assistant","content":[{"type":"text","text":"done"}]},"parent_tool_use_id":null,"session_id":"a5984ed8-b509-4f00-9d68-025be0f5f129"}
{"type":"result","subtype":"success","is_error":false,"result":"done","session_id":"a5984ed8-b509-4f00-9d68-025be0f5f129","num_turns":2}
```

`claude-partial-turn.jsonl` (with `--include-partial-messages`)
```jsonl
{"type":"system","subtype":"init","cwd":"/private/tmp/work","session_id":"3828fcae-6391-4c6c-b69f-f7bb9354d5cf"}
{"type":"system","subtype":"status","status":"requesting","session_id":"3828fcae-6391-4c6c-b69f-f7bb9354d5cf"}
{"type":"stream_event","event":{"type":"message_start","message":{"id":"msg_3","role":"assistant","content":[]}},"parent_tool_use_id":null,"session_id":"3828fcae-6391-4c6c-b69f-f7bb9354d5cf"}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":null,"session_id":"3828fcae-6391-4c6c-b69f-f7bb9354d5cf"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hi "}},"parent_tool_use_id":null,"session_id":"3828fcae-6391-4c6c-b69f-f7bb9354d5cf"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"there"}},"parent_tool_use_id":null,"session_id":"3828fcae-6391-4c6c-b69f-f7bb9354d5cf"}
{"type":"assistant","message":{"id":"msg_3","role":"assistant","content":[{"type":"text","text":"hi there"}]},"parent_tool_use_id":null,"session_id":"3828fcae-6391-4c6c-b69f-f7bb9354d5cf"}
{"type":"stream_event","event":{"type":"content_block_stop","index":0},"parent_tool_use_id":null,"session_id":"3828fcae-6391-4c6c-b69f-f7bb9354d5cf"}
{"type":"stream_event","event":{"type":"message_stop"},"parent_tool_use_id":null,"session_id":"3828fcae-6391-4c6c-b69f-f7bb9354d5cf"}
{"type":"result","subtype":"success","is_error":false,"result":"hi there","session_id":"3828fcae-6391-4c6c-b69f-f7bb9354d5cf"}
```

- [ ] **Step 2: Write the failing tests**

```swift
import Foundation
import Testing
@testable import XBotBrain

func fixtureLines(_ name: String) throws -> [String] {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
}

@Suite struct ClaudeStreamTests {
    @Test func aToolTurnBecomesSessionToolCallResultAndDone() throws {
        let events = try fixtureLines("claude-tool-turn").flatMap(HarnessKind.claude.events(from:))
        #expect(events == [
            .session("a5984ed8-b509-4f00-9d68-025be0f5f129"),
            .toolCall(id: "toolu_01", name: "Read", summary: "/private/tmp/work/a.txt"),
            .toolResult(id: "toolu_01", output: "1\thello\n2\t", isError: false),
            .done,
        ])
    }

    /// Text comes only from the deltas. The whole `assistant` message repeats it, and taking both
    /// would print every reply twice.
    @Test func partialTextComesFromDeltasOnly() throws {
        let events = try fixtureLines("claude-partial-turn").flatMap(HarnessKind.claude.events(from:))
        #expect(events == [
            .session("3828fcae-6391-4c6c-b69f-f7bb9354d5cf"),
            .textDelta("hi "), .textDelta("there"),
            .done,
        ])
    }

    @Test func anErrorResultIsAFailureWithItsReason() {
        let line = #"{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["Credit balance is too low"]}"#
        #expect(HarnessKind.claude.events(from: line) == [.failed("Credit balance is too low")])
    }

    @Test func aSubagentsTextIsNotTheReply() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"inner"}},"parent_tool_use_id":"toolu_9"}"#
        #expect(HarnessKind.claude.events(from: line).isEmpty)
    }

    @Test func toolResultContentMayBeABlockArray() {
        let line = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":[{"type":"text","text":"no such file"}]}]},"parent_tool_use_id":null}"#
        #expect(HarnessKind.claude.events(from: line) == [.toolResult(id: "t1", output: "no such file", isError: true)])
    }

    @Test func garbageIsIgnored() {
        #expect(HarnessKind.claude.events(from: "not json").isEmpty)
        #expect(HarnessKind.claude.events(from: "").isEmpty)
        #expect(HarnessKind.claude.events(from: "[1,2]").isEmpty)
    }

    @Test func argumentsNeverCarryThePrompt() {
        let request = TurnRequest(
            prompt: "--help me", directory: URL(filePath: "/tmp"), model: "opus",
            mode: .editFiles, resumeID: "abc"
        )
        #expect(HarnessKind.claude.arguments(for: request) == [
            "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--permission-mode", "acceptEdits", "--model", "opus", "--resume", "abc",
        ])
    }
}
```

- [ ] **Step 3: Run to see it fail.** `swift test --filter ClaudeStreamTests` → compile errors (types missing).

- [ ] **Step 4: Implement.**

`BrainEvent.swift`
```swift
import Foundation

/// Everything a brain says during one turn, in order.
///
/// Both brains — an agent CLI driven as a harness, and later the native loop — speak this and
/// nothing else, so the transcript never knows which one it is showing.
public enum BrainEvent: Equatable, Sendable {
    /// The brain's own id for this conversation. Passed back as `TurnRequest.resumeID` next turn.
    case session(String)
    /// A piece of streamed reply text, appended to the text block in progress.
    case textDelta(String)
    /// A whole block of reply text that arrives at once.
    case text(String)
    case toolCall(id: String, name: String, summary: String)
    case toolResult(id: String, output: String, isError: Bool)
    /// Something the harness said that is not part of the reply, such as a config warning.
    case notice(String)
    case done
    case failed(String)

    public var isTerminal: Bool {
        switch self {
        case .done, .failed: true
        default: false
        }
    }
}

public enum PermissionMode: String, Codable, CaseIterable, Sendable {
    /// Reads and answers; changes to the folder are refused.
    case readOnly
    /// Edits files in the folder.
    case editFiles
    /// Anything, without asking.
    case fullAccess
}

public struct TurnRequest: Equatable, Sendable {
    public var prompt: String
    public var directory: URL
    /// Nil means the CLI's own default.
    public var model: String?
    public var mode: PermissionMode
    public var resumeID: String?

    public init(
        prompt: String,
        directory: URL,
        model: String? = nil,
        mode: PermissionMode,
        resumeID: String? = nil
    ) {
        self.prompt = prompt
        self.directory = directory
        self.model = model
        self.mode = mode
        self.resumeID = resumeID
    }
}

public protocol Brain: Sendable {
    /// One turn. The stream ends with exactly one `.done` or `.failed`, and cancelling the task
    /// that consumes it stops the turn.
    func run(_ request: TurnRequest) -> AsyncStream<BrainEvent>
}
```

`JSONLine.swift`
```swift
import Foundation

/// One line of a CLI's JSON stream, as a dictionary, or nil for anything else. A harness prints
/// banners and warnings between its JSON lines; those are not ours to fail on.
func jsonObject(_ line: String) -> [String: Any]? {
    guard line.first == "{" else { return nil }
    return (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
}

/// What a tool call is about, on one line: its file, command, pattern or address.
func summary(of input: Any?) -> String {
    guard let input = input as? [String: Any] else { return "" }
    for key in ["file_path", "path", "command", "pattern", "url", "query", "description"] {
        if let value = input[key] as? String { return oneLine(value) }
    }
    return ""
}

func oneLine(_ text: String, limit: Int = 160) -> String {
    let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        .trimmingCharacters(in: .whitespaces)
    return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
}
```

`ClaudeStream.swift`
```swift
import Foundation

/// Claude Code's `--output-format stream-json`, run with `--include-partial-messages`.
///
/// Text is read from the `stream_event` deltas only: the complete `assistant` message that follows
/// repeats it. Tool calls are read from the `assistant` message, where their input is whole.
/// Anything a subagent says (`parent_tool_use_id` set) belongs to that subagent, not the reply.
enum ClaudeStream {
    static func events(from line: String) -> [BrainEvent] {
        guard let object = jsonObject(line) else { return [] }
        let topLevel = object["parent_tool_use_id"] == nil || object["parent_tool_use_id"] is NSNull

        switch object["type"] as? String {
        case "system":
            guard object["subtype"] as? String == "init",
                  let id = object["session_id"] as? String else { return [] }
            return [.session(id)]

        case "stream_event":
            guard topLevel,
                  let event = object["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return [] }
            return [.textDelta(text)]

        case "assistant":
            guard topLevel else { return [] }
            return blocks(of: object).compactMap { block in
                guard block["type"] as? String == "tool_use",
                      let id = block["id"] as? String,
                      let name = block["name"] as? String else { return nil }
                return .toolCall(id: id, name: name, summary: summary(of: block["input"]))
            }

        case "user":
            guard topLevel else { return [] }
            return blocks(of: object).compactMap { block in
                guard block["type"] as? String == "tool_result",
                      let id = block["tool_use_id"] as? String else { return nil }
                return .toolResult(
                    id: id,
                    output: text(of: block["content"]),
                    isError: block["is_error"] as? Bool ?? false
                )
            }

        case "result":
            if object["is_error"] as? Bool == true || object["subtype"] as? String != "success" {
                let reason = (object["errors"] as? [String])?.joined(separator: "\n")
                    ?? (object["result"] as? String)
                    ?? String(localized: "Claude Code stopped with an error.")
                return [.failed(reason)]
            }
            return [.done]

        default:
            return []
        }
    }

    private static func blocks(of object: [String: Any]) -> [[String: Any]] {
        ((object["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
    }

    /// A tool result's content is a string, or a list of blocks of which only text is readable.
    private static func text(of content: Any?) -> String {
        if let string = content as? String { return string }
        let blocks = content as? [[String: Any]] ?? []
        return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
}
```

`HarnessKind.swift`
```swift
import Foundation

/// An agent CLI the person has installed and signed in to, which xBot drives on their subscription.
public enum HarnessKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex

    /// Product names, so not localised.
    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var executableName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    /// What the composer offers. `nil` first: the CLI's own default, whatever it is this week.
    public var models: [String?] {
        switch self {
        case .claude: [nil, "opus", "sonnet", "haiku"]
        case .codex: [nil]
        }
    }

    /// Never the prompt: it goes on stdin, because a prompt starting with "-" would be read as a
    /// flag and argv has a length limit.
    public func arguments(for request: TurnRequest) -> [String] {
        switch self {
        case .claude:
            let mode = switch request.mode {
            case .readOnly: "default"
            case .editFiles: "acceptEdits"
            case .fullAccess: "bypassPermissions"
            }
            var arguments = [
                "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                "--permission-mode", mode,
            ]
            if let model = request.model { arguments += ["--model", model] }
            if let resume = request.resumeID { arguments += ["--resume", resume] }
            return arguments

        case .codex:
            let sandbox = switch request.mode {
            case .readOnly: "read-only"
            case .editFiles: "workspace-write"
            case .fullAccess: "danger-full-access"
            }
            // `-c` rather than `-s`: `exec resume` has no `-s`, and one spelling for both is simpler.
            var arguments = ["exec"]
            if request.resumeID != nil { arguments.append("resume") }
            arguments += ["--json", "--skip-git-repo-check", "-c", "sandbox_mode=\"\(sandbox)\""]
            if let model = request.model { arguments += ["-m", model] }
            if let resume = request.resumeID { arguments.append(resume) }
            arguments.append("-")
            return arguments
        }
    }

    public func events(from line: String) -> [BrainEvent] {
        switch self {
        case .claude: ClaudeStream.events(from: line)
        case .codex: CodexStream.events(from: line)
        }
    }
}
```
(Until Task 3, `CodexStream.events` is `enum CodexStream { static func events(from line: String) -> [BrainEvent] { [] } }` in `CodexStream.swift`.)

- [ ] **Step 5: Run.** `swift test --filter ClaudeStreamTests` → PASS.
- [ ] **Step 6: Commit** — `"Brain events, and Claude Code's stream read into them."`

---

### Task 3: The Codex stream

**Files:**
- Modify: `apps/mac/Sources/XBotBrain/CodexStream.swift`
- Create: `apps/mac/Tests/XBotBrainTests/Fixtures/codex-tool-turn.jsonl`
- Test: `apps/mac/Tests/XBotBrainTests/CodexStreamTests.swift`

**Interfaces:**
- Consumes: `BrainEvent`, `jsonObject`, `oneLine` (Task 2).
- Produces: `CodexStream.events(from:)` via `HarnessKind.codex.events(from:)`.

- [ ] **Step 1: Fixture** (from a real `codex exec --json` run, home path anonymised):

```jsonl
{"type":"thread.started","thread_id":"01a11205-6008-78f2-91ed-0b83eef8ca4c"}
{"type":"item.completed","item":{"id":"item_0","type":"error","message":"Codex is ignoring 2 unrecognized configuration settings."}}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"I’ll read `a.txt` with a shell command."}}
{"type":"item.started","item":{"id":"item_4","type":"command_execution","command":"/bin/zsh -lc 'cat a.txt'","aggregated_output":"","exit_code":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_4","type":"command_execution","command":"/bin/zsh -lc 'cat a.txt'","aggregated_output":"hello\n","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_5","type":"agent_message","text":"done"}}
{"type":"turn.completed","usage":{"input_tokens":39746,"output_tokens":56}}
```

- [ ] **Step 2: Failing tests**

```swift
import Testing
@testable import XBotBrain

@Suite struct CodexStreamTests {
    @Test func aToolTurn() throws {
        let events = try fixtureLines("codex-tool-turn").flatMap(HarnessKind.codex.events(from:))
        #expect(events == [
            .session("01a11205-6008-78f2-91ed-0b83eef8ca4c"),
            .notice("Codex is ignoring 2 unrecognized configuration settings."),
            .text("I’ll read `a.txt` with a shell command."),
            .toolCall(id: "item_4", name: "Shell", summary: "cat a.txt"),
            .toolResult(id: "item_4", output: "hello\n", isError: false),
            .text("done"),
            .done,
        ])
    }

    @Test func aFailedCommandIsAnErrorResult() {
        let line = #"{"type":"item.completed","item":{"id":"i","type":"command_execution","command":"ls nope","aggregated_output":"ls: nope: No such file","exit_code":1,"status":"failed"}}"#
        #expect(HarnessKind.codex.events(from: line) == [.toolResult(id: "i", output: "ls: nope: No such file", isError: true)])
    }

    @Test func fileChangesShowTheirPaths() {
        let line = #"{"type":"item.completed","item":{"id":"f","type":"file_change","changes":[{"path":"a.txt","kind":"update"},{"path":"b.txt","kind":"add"}],"status":"completed"}}"#
        #expect(HarnessKind.codex.events(from: line) == [
            .toolCall(id: "f", name: "Edit", summary: "a.txt, b.txt"),
            .toolResult(id: "f", output: "", isError: false),
        ])
    }

    /// A top-level `error` can be a reconnect that recovers; only `turn.failed` ends the turn.
    @Test func onlyTurnFailedEndsTheTurn() {
        #expect(HarnessKind.codex.events(from: #"{"type":"error","message":"Reconnecting… 1/5"}"#) == [.notice("Reconnecting… 1/5")])
        #expect(HarnessKind.codex.events(from: #"{"type":"turn.failed","error":{"message":"usage limit reached"}}"#) == [.failed("usage limit reached")])
    }

    @Test func resumeArgumentsPutTheIDBeforeTheStdinMarker() {
        let request = TurnRequest(prompt: "x", directory: URL(filePath: "/tmp"), mode: .readOnly, resumeID: "t-1")
        #expect(HarnessKind.codex.arguments(for: request) == [
            "exec", "resume", "--json", "--skip-git-repo-check", "-c", "sandbox_mode=\"read-only\"", "t-1", "-",
        ])
    }
}
```
(Add `import Foundation` for `URL`.)

- [ ] **Step 3: Run** → FAIL (empty events).

- [ ] **Step 4: Implement**

```swift
import Foundation

/// Codex's `exec --json` stream. Items arrive whole, so text is `.text`, not deltas.
enum CodexStream {
    static func events(from line: String) -> [BrainEvent] {
        guard let object = jsonObject(line) else { return [] }
        let item = object["item"] as? [String: Any]
        let id = item?["id"] as? String ?? ""

        switch object["type"] as? String {
        case "thread.started":
            return (object["thread_id"] as? String).map { [.session($0)] } ?? []

        case "item.started":
            guard item?["type"] as? String == "command_execution" else { return [] }
            return [.toolCall(id: id, name: "Shell", summary: command(item?["command"]))]

        case "item.completed":
            switch item?["type"] as? String {
            case "agent_message":
                return (item?["text"] as? String).map { [.text($0)] } ?? []
            case "command_execution":
                let exit = item?["exit_code"] as? Int ?? 0
                return [.toolResult(id: id, output: item?["aggregated_output"] as? String ?? "", isError: exit != 0)]
            case "file_change":
                let paths = (item?["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
                return [
                    .toolCall(id: id, name: "Edit", summary: oneLine(paths.joined(separator: ", "))),
                    .toolResult(id: id, output: "", isError: item?["status"] as? String == "failed"),
                ]
            case "error":
                return (item?["message"] as? String).map { [.notice(oneLine($0))] } ?? []
            default:
                return []
            }

        case "turn.completed":
            return [.done]

        case "turn.failed":
            let message = (object["error"] as? [String: Any])?["message"] as? String
            return [.failed(message ?? String(localized: "Codex stopped with an error."))]

        case "error":
            return (object["message"] as? String).map { [.notice(oneLine($0))] } ?? []

        default:
            return []
        }
    }

    /// Codex wraps every command in the login shell (`/bin/zsh -lc '…'`). Show what it ran.
    private static func command(_ value: Any?) -> String {
        let full = value as? String ?? ""
        if let match = full.wholeMatch(of: /\S+ -lc '(.*)'/) { return oneLine(String(match.1)) }
        return oneLine(full)
    }
}
```
Note the notice in the fixture is one line, so `oneLine` leaves it unchanged.

- [ ] **Step 5: Run** → PASS. **Step 6: Commit** — `"Codex's stream read into brain events."`

---

### Task 4: Running a harness

**Files:**
- Create: `apps/mac/Sources/XBotBrain/HarnessBrain.swift`
- Test: `apps/mac/Tests/XBotBrainTests/HarnessBrainTests.swift`

**Interfaces:**
- Consumes: `HarnessKind.arguments(for:)`, `HarnessKind.events(from:)`, `Brain`, `TurnRequest`.
- Produces: `public struct HarnessBrain: Brain { public init(kind: HarnessKind, executable: URL, environment: [String: String]) }`

- [ ] **Step 1: Failing tests.** Each test writes a fake CLI — a shell script — that prints fixture lines and records its stdin and arguments.

```swift
import Foundation
import Testing
@testable import XBotBrain

/// A stand-in CLI. `body` is a shell script; `$OUT` is a folder it can write evidence into.
func fakeCLI(_ body: String) throws -> (url: URL, out: URL) {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let script = dir.appending(path: "cli")
    try "#!/bin/sh\nOUT='\(dir.path)'\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return (script, dir)
}

func collect(_ stream: AsyncStream<BrainEvent>) async -> [BrainEvent] {
    var events: [BrainEvent] = []
    for await event in stream { events.append(event) }
    return events
}

@Suite struct HarnessBrainTests {
    let tmp = URL(filePath: NSTemporaryDirectory())

    @Test func streamsEventsInOrderAndEndsOnce() async throws {
        let cli = try fakeCLI("""
        cat > /dev/null
        echo '{"type":"system","subtype":"init","session_id":"s1"}'
        echo 'a banner that is not json'
        echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}},"parent_tool_use_id":null}'
        echo '{"type":"result","subtype":"success","is_error":false}'
        echo '{"type":"result","subtype":"success","is_error":false}'
        """)
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        let events = await collect(brain.run(TurnRequest(prompt: "hello", directory: tmp, mode: .readOnly)))
        #expect(events == [.session("s1"), .textDelta("hi"), .done])
    }

    @Test func promptTravelsOnStdinEvenWhenItLooksLikeAFlag() async throws {
        let cli = try fakeCLI("""
        cat > "$OUT/stdin"
        printf '%s\\n' "$@" > "$OUT/args"
        echo '{"type":"result","subtype":"success","is_error":false}'
        """)
        let prompt = "--dangerously-skip-permissions " + String(repeating: "long ", count: 50_000)
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        _ = await collect(brain.run(TurnRequest(prompt: prompt, directory: tmp, mode: .readOnly)))
        #expect(try String(contentsOf: cli.out.appending(path: "stdin"), encoding: .utf8) == prompt)
        #expect(try !String(contentsOf: cli.out.appending(path: "args"), encoding: .utf8).contains("dangerously"))
    }

    @Test func exitWithoutAResultIsAFailure() async throws {
        let cli = try fakeCLI("cat > /dev/null; echo 'not logged in' >&2; exit 3")
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        let events = await collect(brain.run(TurnRequest(prompt: "x", directory: tmp, mode: .readOnly)))
        #expect(events.count == 1)
        guard case .failed(let reason) = events.first else { Issue.record("expected failure"); return }
        #expect(reason.contains("not logged in"))
    }

    @Test func missingFolderFailsWithoutSpawning() async throws {
        let cli = try fakeCLI("touch \"$OUT/ran\"")
        let gone = tmp.appending(path: "xbot-missing-\(UUID().uuidString)")
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        let events = await collect(brain.run(TurnRequest(prompt: "x", directory: gone, mode: .readOnly)))
        guard case .failed(let reason) = events.first else { Issue.record("expected failure"); return }
        #expect(reason.contains(gone.path))
        #expect(!FileManager.default.fileExists(atPath: cli.out.appending(path: "ran").path))
    }

    @Test func runsInTheRequestedFolderWithTheGivenEnvironment() async throws {
        let cli = try fakeCLI("""
        cat > /dev/null
        pwd -P > "$OUT/pwd"; echo "$XBOT_MARK" > "$OUT/env"
        echo '{"type":"result","subtype":"success","is_error":false}'
        """)
        let folder = tmp.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: ["XBOT_MARK": "yes"])
        _ = await collect(brain.run(TurnRequest(prompt: "x", directory: folder, mode: .readOnly)))
        let pwd = try String(contentsOf: cli.out.appending(path: "pwd"), encoding: .utf8)
        #expect(pwd.trimmingCharacters(in: .newlines) == folder.resolvingSymlinksInPath().path)
        #expect(try String(contentsOf: cli.out.appending(path: "env"), encoding: .utf8) == "yes\n")
    }

    @Test func cancellingStopsTheProcess() async throws {
        let cli = try fakeCLI("""
        cat > /dev/null
        echo '{"type":"system","subtype":"init","session_id":"s"}'
        trap 'touch "$OUT/terminated"; exit 0' TERM
        while true; do sleep 0.05; done
        """)
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        let task = Task { await collect(brain.run(TurnRequest(prompt: "x", directory: tmp, mode: .readOnly))) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        _ = await task.value
        let marker = cli.out.appending(path: "terminated").path
        for _ in 0..<40 where !FileManager.default.fileExists(atPath: marker) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(FileManager.default.fileExists(atPath: marker))
    }
}
```

- [ ] **Step 2: Run** → FAIL (no `HarnessBrain`).

- [ ] **Step 3: Implement**

```swift
import Foundation
import Synchronization

/// One turn of an installed agent CLI, as a stream of `BrainEvent`s.
///
/// A fresh process per turn, resumed by the CLI's own session id. That is how monocode drives the
/// same CLIs, and it means a crashed turn cannot leave a wedged process behind for the next one.
public struct HarnessBrain: Brain {
    public let kind: HarnessKind
    public let executable: URL
    public let environment: [String: String]

    public init(kind: HarnessKind, executable: URL, environment: [String: String]) {
        self.kind = kind
        self.executable = executable
        self.environment = environment
    }

    public func run(_ request: TurnRequest) -> AsyncStream<BrainEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: BrainEvent.self)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: request.directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            continuation.yield(.failed(String(
                localized: "This chat's folder is no longer at \(request.directory.path). Move it back, or start a new chat."
            )))
            continuation.finish()
            return stream
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = kind.arguments(for: request)
        process.currentDirectoryURL = request.directory
        process.environment = environment
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let stderr = Tail()
        errors.fileHandleForReading.readabilityHandler = { stderr.append($0.availableData) }
        let exit = AsyncStream.makeStream(of: Int32.self)
        let exited = Atomic(false)
        process.terminationHandler = { finished in
            exited.store(true, ordering: .sequentiallyConsistent)
            exit.continuation.yield(finished.terminationStatus)
            exit.continuation.finish()
        }

        do {
            try process.run()
        } catch {
            continuation.yield(.failed(String(localized: "\(kind.displayName) could not start: \(error.localizedDescription)")))
            continuation.finish()
            return stream
        }

        let pid = process.processIdentifier
        // ponytail: SIGTERM to the CLI only; it tears down its own tool processes. Kill the process
        // group instead if one is ever seen surviving.
        continuation.onTermination = { _ in
            if !exited.load(ordering: .sequentiallyConsistent) { kill(pid, SIGTERM) }
        }

        // The prompt goes on stdin, never argv. Written off this thread so a huge prompt cannot
        // block the caller while the CLI is busy printing.
        let writer = input.fileHandleForWriting
        let prompt = Data(request.prompt.utf8)
        Task.detached {
            try? writer.write(contentsOf: prompt)
            try? writer.close()
        }

        let kind = self.kind
        Task.detached {
            var ended = false
            do {
                for try await line in output.fileHandleForReading.bytes.lines {
                    for event in kind.events(from: line) where !ended {
                        continuation.yield(event)
                        ended = event.isTerminal
                    }
                }
            } catch {}
            var status: Int32 = 0
            for await code in exit.stream { status = code }
            errors.fileHandleForReading.readabilityHandler = nil
            if !ended {
                let said = stderr.text.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.yield(.failed(said.isEmpty
                    ? String(localized: "\(kind.displayName) stopped before finishing (exit code \(status)).")
                    : said))
            }
            continuation.finish()
        }
        return stream
    }
}

/// The last few kilobytes a process wrote to stderr: where a CLI explains why it gave up.
private final class Tail: Sendable {
    private let data = Mutex(Data())
    private let limit = 4096

    func append(_ chunk: Data) {
        data.withLock { data in
            data.append(chunk)
            if data.count > limit { data.removeFirst(data.count - limit) }
        }
    }

    var text: String { data.withLock { String(decoding: $0, as: UTF8.self) } }
}
```

- [ ] **Step 4: Run** `swift test --filter HarnessBrainTests` 10 times (`for i in $(seq 10); do swift test --filter HarnessBrainTests || break; done`) — processes and timing are where flakes live. Expected: PASS every time.
- [ ] **Step 5: Commit** — `"Run an agent CLI per turn: prompt on stdin, one terminal event, stop on cancel."`

---

### Task 5: Finding the installed CLIs

**Files:**
- Create: `apps/mac/Sources/XBotBrain/HarnessLocator.swift`
- Test: `apps/mac/Tests/XBotBrainTests/HarnessLocatorTests.swift`

**Interfaces:**
- Produces:
  - `HarnessLocator.searchPath(loginShellPath: String?, home: String) -> String`
  - `HarnessLocator.find(_ kind: HarnessKind, in path: String) -> URL?`
  - `HarnessLocator.environment(path: String, base: [String: String]) -> [String: String]`
  - `HarnessLocator.loginShellPath(shell: String) async -> String?`
  - `HarnessLocator.installed() async -> [HarnessKind: any Brain]`

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
@testable import XBotBrain

@Suite struct HarnessLocatorTests {
    @Test func findsOnlyExecutables() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let claude = dir.appending(path: "claude")
        try "#!/bin/sh\n".write(to: claude, atomically: true, encoding: .utf8)
        try "".write(to: dir.appending(path: "codex"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)

        #expect(HarnessLocator.find(.claude, in: "/nope:\(dir.path)") == claude)
        #expect(HarnessLocator.find(.codex, in: dir.path) == nil)
    }

    /// Launched from Claude Code during development, these are set, and a nested `claude` refuses
    /// to start inside what it thinks is its own session.
    @Test func environmentDropsClaudeCodesOwnMarkers() {
        let env = HarnessLocator.environment(path: "/a:/b", base: [
            "HOME": "/Users/me", "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli", "PATH": "/usr/bin",
        ])
        #expect(env == ["HOME": "/Users/me", "PATH": "/a:/b"])
    }

    @Test func searchPathPutsTheShellsFirstAndAddsTheUsualPlaces() {
        let path = HarnessLocator.searchPath(loginShellPath: "/custom/bin:/usr/bin", home: "/Users/me")
        let parts = path.split(separator: ":").map(String.init)
        #expect(parts.first == "/custom/bin")
        #expect(parts.contains("/Users/me/.local/bin"))
        #expect(parts.contains("/opt/homebrew/bin"))
        #expect(Set(parts).count == parts.count)
    }

    @Test func loginShellPathReadsBetweenMarkersAndIgnoresNoise() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let shell = dir.appending(path: "fakesh")
        // Prints a greeting the way a chatty .zshrc does, then runs the command it was given.
        try "#!/bin/sh\necho 'welcome back!'\nfor a; do last=$a; done\nPATH=/from/shell:/usr/bin /bin/sh -c \"$last\"\n"
            .write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        #expect(await HarnessLocator.loginShellPath(shell: shell.path) == "/from/shell:/usr/bin")
    }
}
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Where the agent CLIs live on this Mac.
///
/// An app started from the Dock inherits launchd's bare PATH, which contains none of the places
/// these CLIs install to, and the CLIs themselves need the person's PATH to run their tools. So
/// the PATH comes from the person's login shell, with the usual install folders added in case the
/// shell is slow or strange.
public enum HarnessLocator {
    private static let marker = "__XBOT_PATH__"

    public static func installed() async -> [HarnessKind: any Brain] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let path = searchPath(loginShellPath: await loginShellPath(shell: shell), home: home)
        let env = environment(path: path, base: ProcessInfo.processInfo.environment)
        var found: [HarnessKind: any Brain] = [:]
        for kind in HarnessKind.allCases {
            if let url = find(kind, in: path) {
                found[kind] = HarnessBrain(kind: kind, executable: url, environment: env)
            }
        }
        return found
    }

    public static func searchPath(loginShellPath: String?, home: String) -> String {
        let usual = [
            "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin",
            "\(home)/.bun/bin", "\(home)/.claude/local", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        var seen = Set<String>()
        return ((loginShellPath ?? "").split(separator: ":").map(String.init) + usual)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
    }

    public static func find(_ kind: HarnessKind, in path: String) -> URL? {
        path.split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: kind.executableName) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static func environment(path: String, base: [String: String]) -> [String: String] {
        var env = base.filter { !$0.key.hasPrefix("CLAUDECODE") && !$0.key.hasPrefix("CLAUDE_CODE_") }
        env["PATH"] = path
        return env
    }

    /// PATH as an interactive login shell sets it, or nil after five seconds. Markers around the
    /// value, because a shell's startup files are allowed to print whatever they like.
    public static func loginShellPath(shell: String) async -> String? {
        let process = Process()
        process.executableURL = URL(filePath: shell)
        process.arguments = ["-l", "-i", "-c", "printf '\(marker)%s\(marker)' \"$PATH\""]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }

        let pid = process.processIdentifier
        let timeout = Task.detached {
            try await Task.sleep(for: .seconds(5))
            kill(pid, SIGKILL)
        }
        let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        timeout.cancel()
        let text = String(decoding: data, as: UTF8.self)
        let parts = text.components(separatedBy: marker)
        return parts.count >= 3 && !parts[1].isEmpty ? parts[1] : nil
    }
}
```
(The fake shell runs its last argument, which is the `-c` command, with a PATH of its own.)

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `"Find installed agent CLIs on the person's PATH."`

---

### Task 6: The store

**Files:**
- Create: `apps/mac/Sources/XBotCore/Database.swift`, `apps/mac/Sources/XBotCore/Models.swift`, `apps/mac/Sources/XBotCore/Store.swift`
- Test: `apps/mac/Tests/XBotCoreTests/StoreTests.swift`, `apps/mac/Tests/XBotCoreTests/PartsTests.swift`

**Interfaces:**
- Consumes: `HarnessKind`, `PermissionMode`, `BrainEvent` from `XBotBrain`.
- Produces:
  - `struct Project: Identifiable, Equatable, Sendable { id: UUID; name: String; path: String; createdAt: Date }` + `var url: URL`
  - `struct Chat: Identifiable, Equatable, Sendable { id: UUID; projectID: UUID?; title: String; harness: HarnessKind; model: String?; mode: PermissionMode; sessionID: String?; createdAt: Date; updatedAt: Date }`
  - `enum Role: String, Codable, Sendable { case user, assistant }`
  - `struct ToolPart: Codable, Equatable, Sendable { id, name, summary: String; output: String?; isError: Bool }`
  - `enum Part: Codable, Equatable, Sendable { case text(String), tool(ToolPart), notice(String), failure(String) }`
  - `extension Array where Element == Part { mutating func apply(_ event: BrainEvent) }`
  - `struct ChatMessage: Identifiable, Equatable, Sendable { id: UUID; chatID: UUID; role: Role; parts: [Part]; createdAt: Date }`
  - `@MainActor final class Store { init(database: Database) throws; static func live() throws -> Store; static func inMemory() -> Store; projects() -> [Project]; save(_ project: Project); deleteProject(_ id: UUID); chats() -> [Chat]; save(_ chat: Chat); deleteChat(_ id: UUID); messages(in chatID: UUID) -> [ChatMessage]; append(_ message: ChatMessage) }` — the read/write methods `throws`.

- [ ] **Step 1: Failing tests**

`PartsTests.swift`
```swift
import Testing
import XBotBrain
@testable import XBotCore

@Suite struct PartsTests {
    @Test func deltasJoinAndToolsSplitText() {
        var parts: [Part] = []
        for event: BrainEvent in [
            .session("s"), .textDelta("Let me "), .textDelta("look."),
            .toolCall(id: "t", name: "Read", summary: "a.txt"),
            .toolResult(id: "t", output: "hello", isError: false),
            .textDelta("It says hello."), .done,
        ] { parts.apply(event) }
        #expect(parts == [
            .text("Let me look."),
            .tool(ToolPart(id: "t", name: "Read", summary: "a.txt", output: "hello", isError: false)),
            .text("It says hello."),
        ])
    }

    @Test func wholeTextBlocksStaySeparate() {
        var parts: [Part] = []
        parts.apply(.text("one")); parts.apply(.text("two"))
        #expect(parts == [.text("one"), .text("two")])
    }

    @Test func failureAndNoticeAreKept() {
        var parts: [Part] = []
        parts.apply(.notice("warn")); parts.apply(.failed("boom"))
        #expect(parts == [.notice("warn"), .failure("boom")])
    }
}
```

`StoreTests.swift`
```swift
import Foundation
import Testing
import XBotBrain
@testable import XBotCore

@MainActor @Suite struct StoreTests {
    let store = Store.inMemory()

    func chat(project: UUID? = nil) -> Chat {
        Chat(id: UUID(), projectID: project, title: "New chat", harness: .claude, model: nil,
             mode: .editFiles, sessionID: nil, createdAt: .now, updatedAt: .now)
    }

    @Test func projectsRoundTrip() throws {
        let project = Project(id: UUID(), name: "site", path: "/tmp/site", createdAt: .now)
        try store.save(project)
        #expect(try store.projects().map(\.path) == ["/tmp/site"])
    }

    @Test func messagesKeepTheirOrderAndParts() throws {
        let c = chat(); try store.save(c)
        let first = ChatMessage(id: UUID(), chatID: c.id, role: .user, parts: [.text("hi")], createdAt: .now)
        let second = ChatMessage(id: UUID(), chatID: c.id, role: .assistant, parts: [
            .text("hello"), .tool(ToolPart(id: "t", name: "Read", summary: "a", output: nil, isError: false)),
        ], createdAt: first.createdAt)
        try store.append(first); try store.append(second)
        #expect(try store.messages(in: c.id) == [first, second])
    }

    /// An upsert written as INSERT OR REPLACE deletes the row first, and the cascade would take
    /// every message in the chat with it.
    @Test func savingAChatAgainKeepsItsMessages() throws {
        var c = chat(); try store.save(c)
        try store.append(ChatMessage(id: UUID(), chatID: c.id, role: .user, parts: [.text("x")], createdAt: .now))
        c.sessionID = "s1"; c.title = "Renamed"
        try store.save(c)
        #expect(try store.messages(in: c.id).count == 1)
        #expect(try store.chats().first?.sessionID == "s1")
    }

    @Test func deletingAProjectDeletesItsChats() throws {
        let project = Project(id: UUID(), name: "p", path: "/tmp/p", createdAt: .now)
        try store.save(project)
        try store.save(chat(project: project.id))
        try store.save(chat())
        try store.deleteProject(project.id)
        #expect(try store.chats().count == 1)
    }

    @Test func chatsAreNewestFirst() throws {
        var old = chat(); old.updatedAt = .distantPast
        let new = chat()
        try store.save(old); try store.save(new)
        #expect(try store.chats().map(\.id) == [new.id, old.id])
    }

    @Test func survivesReopening() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/x.sqlite")
        let c = chat()
        do { let s = try Store(database: Database(url: url)); try s.save(c) }
        let reopened = try Store(database: Database(url: url))
        #expect(try reopened.chats().map(\.id) == [c.id])
    }
}
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

`Database.swift`
```swift
import Foundation
import SQLite3

/// The smallest SQLite wrapper that does the job: one connection, a statement prepared per call.
/// ponytail: no statement cache; add one if a profile ever shows prepare time.
public final class Database {
    public enum Value: Equatable {
        case text(String)
        case real(Double)
        case null
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    private var handle: OpaquePointer?

    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try open(url.path)
        try execute("PRAGMA journal_mode = WAL")
    }

    public init(inMemory: Void = ()) throws {
        try open(":memory:")
    }

    deinit { sqlite3_close_v2(handle) }

    private func open(_ path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw Failure(description: message)
        }
        try execute("PRAGMA foreign_keys = ON")
    }

    public func execute(_ sql: String, _ values: [Value] = []) throws {
        _ = try rows(sql, values)
    }

    public func rows(_ sql: String, _ values: [Value] = []) throws -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure(description: message)
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, transient)
            case .real(let number): sqlite3_bind_double(statement, position, number)
            case .null: sqlite3_bind_null(statement, position)
            }
        }

        var result: [[Value]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                result.append((0..<sqlite3_column_count(statement)).map { column in
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_NULL: .null
                    case SQLITE_FLOAT, SQLITE_INTEGER: .real(sqlite3_column_double(statement, column))
                    default: .text(String(cString: sqlite3_column_text(statement, column)))
                    }
                })
            case SQLITE_DONE:
                return result
            default:
                throw Failure(description: message)
            }
        }
    }

    private var message: String { String(cString: sqlite3_errmsg(handle)) }
}

extension Database.Value {
    var string: String? { if case .text(let text) = self { text } else { nil } }
    var date: Date { if case .real(let n) = self { Date(timeIntervalSince1970: n) } else { .distantPast } }
    var uuid: UUID? { string.flatMap(UUID.init(uuidString:)) }
}

extension Optional where Wrapped == String {
    var sql: Database.Value { map(Database.Value.text) ?? .null }
}
```

`Models.swift`
```swift
import Foundation
import XBotBrain

/// A folder on this Mac that chats work in. Any folder — git features appear only when it is a repo.
public struct Project: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var createdAt: Date
    public var url: URL { URL(filePath: path, directoryHint: .isDirectory) }

    public init(id: UUID = UUID(), name: String, path: String, createdAt: Date = .now) {
        self.id = id; self.name = name; self.path = path; self.createdAt = createdAt
    }
}

public struct Chat: Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Nil: an Inbox chat, which works in xBot's own Inbox folder.
    public var projectID: UUID?
    public var title: String
    public var harness: HarnessKind
    public var model: String?
    public var mode: PermissionMode
    /// The CLI's session, so the next turn continues it. Belongs to `harness` and is cleared with it.
    public var sessionID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), projectID: UUID?, title: String, harness: HarnessKind, model: String? = nil,
        mode: PermissionMode, sessionID: String? = nil, createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id; self.projectID = projectID; self.title = title; self.harness = harness
        self.model = model; self.mode = mode; self.sessionID = sessionID
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public enum Role: String, Codable, Sendable {
    case user
    case assistant
}

public struct ToolPart: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    /// Nil while the tool is still running.
    public var output: String?
    public var isError: Bool
}

public enum Part: Codable, Equatable, Sendable {
    case text(String)
    case tool(ToolPart)
    case notice(String)
    case failure(String)
}

public struct ChatMessage: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var chatID: UUID
    public var role: Role
    public var parts: [Part]
    public var createdAt: Date

    public init(id: UUID = UUID(), chatID: UUID, role: Role, parts: [Part], createdAt: Date = .now) {
        self.id = id; self.chatID = chatID; self.role = role; self.parts = parts; self.createdAt = createdAt
    }
}

extension Array where Element == Part {
    /// Fold one brain event into a reply that is being written.
    public mutating func apply(_ event: BrainEvent) {
        switch event {
        case .textDelta(let delta):
            if case .text(let text) = last { self[count - 1] = .text(text + delta) } else { append(.text(delta)) }
        case .text(let text):
            append(.text(text))
        case .toolCall(let id, let name, let summary):
            append(.tool(ToolPart(id: id, name: name, summary: summary, output: nil, isError: false)))
        case .toolResult(let id, let output, let isError):
            if let index = lastIndex(where: { if case .tool(let t) = $0 { t.id == id } else { false } }),
               case .tool(var tool) = self[index] {
                tool.output = output
                tool.isError = isError
                self[index] = .tool(tool)
            }
        case .notice(let text):
            append(.notice(text))
        case .failed(let reason):
            append(.failure(reason))
        case .session, .done:
            break
        }
    }
}
```

`Store.swift`
```swift
import Foundation
import XBotBrain

/// Everything xBot remembers about projects and chats, in one SQLite file.
/// ponytail: on the main actor; the writes are a row at a time. Move to an actor if a profile says so.
@MainActor
public final class Store {
    private let db: Database
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: Database) throws {
        db = database
        try db.execute("""
            CREATE TABLE IF NOT EXISTS projects (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, created_at REAL NOT NULL)
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS chats (
              id TEXT PRIMARY KEY, project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
              title TEXT NOT NULL, harness TEXT NOT NULL, model TEXT, mode TEXT NOT NULL,
              session_id TEXT, created_at REAL NOT NULL, updated_at REAL NOT NULL)
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS messages (
              id TEXT PRIMARY KEY, chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
              role TEXT NOT NULL, parts TEXT NOT NULL, created_at REAL NOT NULL)
            """)
        try db.execute("CREATE INDEX IF NOT EXISTS messages_by_chat ON messages(chat_id)")
    }

    /// `~/Library/Application Support/xBot/xbot.sqlite`.
    public static func live() throws -> Store {
        try Store(database: Database(url: Self.supportDirectory.appending(path: "xbot.sqlite")))
    }

    public static func inMemory() -> Store {
        // An in-memory database cannot fail to open or to take this schema.
        try! Store(database: Database())
    }

    public static var supportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "xBot", directoryHint: .isDirectory)
    }

    // MARK: Projects

    public func projects() throws -> [Project] {
        try db.rows("SELECT id, name, path, created_at FROM projects ORDER BY name COLLATE NOCASE").compactMap { r in
            guard let id = r[0].uuid, let name = r[1].string, let path = r[2].string else { return nil }
            return Project(id: id, name: name, path: path, createdAt: r[3].date)
        }
    }

    public func save(_ project: Project) throws {
        try db.execute("""
            INSERT INTO projects (id, name, path, created_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name, path = excluded.path
            """, [.text(project.id.uuidString), .text(project.name), .text(project.path),
                  .real(project.createdAt.timeIntervalSince1970)])
    }

    public func deleteProject(_ id: UUID) throws {
        try db.execute("DELETE FROM projects WHERE id = ?", [.text(id.uuidString)])
    }

    // MARK: Chats

    public func chats() throws -> [Chat] {
        try db.rows("""
            SELECT id, project_id, title, harness, model, mode, session_id, created_at, updated_at
            FROM chats ORDER BY updated_at DESC
            """).compactMap { r in
            // A row from a newer xBot with a harness this one does not know is skipped, not fatal.
            guard let id = r[0].uuid, let title = r[2].string,
                  let harness = r[3].string.flatMap(HarnessKind.init(rawValue:)),
                  let mode = r[5].string.flatMap(PermissionMode.init(rawValue:)) else { return nil }
            return Chat(id: id, projectID: r[1].uuid, title: title, harness: harness, model: r[4].string,
                        mode: mode, sessionID: r[6].string, createdAt: r[7].date, updatedAt: r[8].date)
        }
    }

    /// An upsert that updates in place. INSERT OR REPLACE would delete the row first, and the
    /// cascade would take the chat's messages with it.
    public func save(_ chat: Chat) throws {
        try db.execute("""
            INSERT INTO chats (id, project_id, title, harness, model, mode, session_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET project_id = excluded.project_id, title = excluded.title,
              harness = excluded.harness, model = excluded.model, mode = excluded.mode,
              session_id = excluded.session_id, updated_at = excluded.updated_at
            """, [.text(chat.id.uuidString), chat.projectID?.uuidString.sql ?? .null, .text(chat.title),
                  .text(chat.harness.rawValue), chat.model.sql, .text(chat.mode.rawValue),
                  chat.sessionID.sql, .real(chat.createdAt.timeIntervalSince1970),
                  .real(chat.updatedAt.timeIntervalSince1970)])
    }

    public func deleteChat(_ id: UUID) throws {
        try db.execute("DELETE FROM chats WHERE id = ?", [.text(id.uuidString)])
    }

    // MARK: Messages

    public func messages(in chatID: UUID) throws -> [ChatMessage] {
        try db.rows(
            "SELECT id, role, parts, created_at FROM messages WHERE chat_id = ? ORDER BY rowid",
            [.text(chatID.uuidString)]
        ).compactMap { r in
            guard let id = r[0].uuid, let role = r[1].string.flatMap(Role.init(rawValue:)),
                  let json = r[2].string,
                  let parts = try? decoder.decode([Part].self, from: Data(json.utf8)) else { return nil }
            return ChatMessage(id: id, chatID: chatID, role: role, parts: parts, createdAt: r[3].date)
        }
    }

    public func append(_ message: ChatMessage) throws {
        let parts = String(decoding: try encoder.encode(message.parts), as: UTF8.self)
        try db.execute(
            "INSERT INTO messages (id, chat_id, role, parts, created_at) VALUES (?, ?, ?, ?, ?)",
            [.text(message.id.uuidString), .text(message.chatID.uuidString), .text(message.role.rawValue),
             .text(parts), .real(message.createdAt.timeIntervalSince1970)]
        )
    }
}
```
Dates round-trip through `Double`, so tests that compare whole structs must create them from values that survive that (the `Date.now` used in the tests does: `timeIntervalSince1970` is a `Double` already).

- [ ] **Step 4: Run** `swift test --filter "StoreTests|PartsTests"` → PASS.
- [ ] **Step 5: Commit** — `"Projects, chats and messages in SQLite."`

---

### Task 7: The workspace

**Files:**
- Create: `apps/mac/Sources/XBotCore/Workspace.swift`
- Test: `apps/mac/Tests/XBotCoreTests/WorkspaceTests.swift`

**Interfaces:**
- Consumes: `Store`, models, `Brain`, `TurnRequest`, `HarnessKind`, `PermissionMode`.
- Produces (`@MainActor @Observable public final class Workspace`):
  - `init(store: Store, inbox: URL, discover: @escaping @Sendable () async -> [HarnessKind: any Brain])`
  - state: `projects: [Project]`, `chats: [Chat]`, `openChatIDs: [UUID]`, `selectedChatID: UUID?`, `live: [UUID: [Part]]`, `problem: String?`, `availableHarnesses: [HarnessKind]`
  - `refreshHarnesses() async`, `chat(_ id: UUID) -> Chat?`, `messages(in id: UUID) -> [ChatMessage]`, `isRunning(_ id: UUID) -> Bool`, `sendBlockedReason(_ id: UUID) -> String?`
  - `addProject(at url: URL) -> Project`, `removeProject(_ id: UUID)`
  - `newChat(in projectID: UUID?) -> Chat?`, `open(_ id: UUID)`, `close(_ id: UUID)`, `rename(_ id: UUID, to title: String)`, `deleteChat(_ id: UUID)`
  - `setHarness(_ kind: HarnessKind, for id: UUID)`, `setModel(_ model: String?, for id: UUID)`, `setMode(_ mode: PermissionMode, for id: UUID)`
  - `send(_ text: String, in id: UUID) -> Bool`, `stop(_ id: UUID)`, `stopAll()`
  - `static func title(from text: String) -> String`

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Synchronization
import Testing
import XBotBrain
@testable import XBotCore

/// Plays a script. With `hold`, it never ends the turn on its own.
final class ScriptedBrain: Brain {
    let script: [BrainEvent]
    let hold: Bool
    let requests = Mutex<[TurnRequest]>([])

    init(_ script: [BrainEvent], hold: Bool = false) { self.script = script; self.hold = hold }

    func run(_ request: TurnRequest) -> AsyncStream<BrainEvent> {
        requests.withLock { $0.append(request) }
        let (stream, continuation) = AsyncStream.makeStream(of: BrainEvent.self)
        for event in script { continuation.yield(event) }
        if !hold { continuation.finish() }
        return stream
    }
}

@MainActor @Suite struct WorkspaceTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    func workspace(_ brain: ScriptedBrain) async -> Workspace {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        return w
    }

    func settle(_ w: Workspace, _ id: UUID) async {
        for _ in 0..<200 where w.isRunning(id) { await Task.yield() }
    }

    @Test func aTurnIsStreamedThenSaved() async throws {
        let brain = ScriptedBrain([.session("s1"), .textDelta("Hel"), .textDelta("lo"), .done])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        #expect(w.send("Say hello to the team", in: chat.id))
        await settle(w, chat.id)

        #expect(w.messages(in: chat.id).map(\.parts) == [[.text("Say hello to the team")], [.text("Hello")]])
        #expect(w.chat(chat.id)?.sessionID == "s1")
        #expect(w.chat(chat.id)?.title == "Say hello to the team")
        #expect(w.live[chat.id] == nil)
    }

    @Test func theNextTurnResumesTheSession() async throws {
        let brain = ScriptedBrain([.session("s1"), .done])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("one", in: chat.id); await settle(w, chat.id)
        _ = w.send("two", in: chat.id); await settle(w, chat.id)
        #expect(brain.requests.withLock { $0.map(\.resumeID) } == [nil, "s1"])
    }

    @Test func sendingWhileRunningIsRefused() async throws {
        let w = await workspace(ScriptedBrain([.textDelta("…")], hold: true))
        let chat = try #require(w.newChat(in: nil))
        #expect(w.send("first", in: chat.id))
        #expect(!w.send("second", in: chat.id))
        #expect(w.messages(in: chat.id).count == 1)
    }

    @Test func stopKeepsThePartialReply() async throws {
        let w = await workspace(ScriptedBrain([.textDelta("Half an ans")], hold: true))
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("go", in: chat.id)
        for _ in 0..<50 { await Task.yield() }
        w.stop(chat.id)
        #expect(!w.isRunning(chat.id))
        let reply = try #require(w.messages(in: chat.id).last)
        #expect(reply.role == .assistant)
        #expect(reply.parts == [.text("Half an ans"), .notice(String(localized: "Stopped."))])
    }

    @Test func aFailureIsSavedInTheReply() async throws {
        let w = await workspace(ScriptedBrain([.failed("Not signed in to Claude Code.")]))
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("hi", in: chat.id); await settle(w, chat.id)
        #expect(w.messages(in: chat.id).last?.parts == [.failure("Not signed in to Claude Code.")])
    }

    @Test func switchingHarnessForgetsTheOldSession() async throws {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: {
            [.claude: ScriptedBrain([.session("s1"), .done]), .codex: ScriptedBrain([.done])]
        })
        await w.refreshHarnesses()
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("one", in: chat.id); await settle(w, chat.id)
        w.setHarness(.codex, for: chat.id)
        #expect(w.chat(chat.id)?.sessionID == nil)
        #expect(w.chat(chat.id)?.model == nil)
    }

    @Test func noHarnessMeansNoChatAndAnHonestReason() async {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [:] })
        await w.refreshHarnesses()
        #expect(w.newChat(in: nil) == nil)
    }

    @Test func aProjectIsAddedOnce() async {
        let w = await workspace(ScriptedBrain([]))
        let a = w.addProject(at: URL(filePath: "/tmp/site"))
        let b = w.addProject(at: URL(filePath: "/tmp/site/"))
        #expect(a.id == b.id)
        #expect(w.projects.count == 1)
        #expect(a.name == "site")
    }

    @Test func projectChatsRunInTheProjectAndInboxChatsInTheInbox() async throws {
        let brain = ScriptedBrain([.done])
        let w = await workspace(brain)
        let project = w.addProject(at: FileManager.default.temporaryDirectory)
        let inProject = try #require(w.newChat(in: project.id))
        let loose = try #require(w.newChat(in: nil))
        _ = w.send("a", in: inProject.id); await settle(w, inProject.id)
        _ = w.send("b", in: loose.id); await settle(w, loose.id)
        #expect(brain.requests.withLock { $0.map(\.directory) } == [project.url, inbox])
        #expect(FileManager.default.fileExists(atPath: inbox.path))
    }

    @Test func titlesAreTheFirstLineShortened() {
        #expect(Workspace.title(from: "  Fix the login bug\nmore detail") == "Fix the login bug")
        #expect(Workspace.title(from: String(repeating: "word ", count: 30)).count <= 49)
    }
}
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation
import Observation
import XBotBrain

/// Projects, chats, and the turns running in them. The one object the window talks to.
@MainActor
@Observable
public final class Workspace {
    public private(set) var projects: [Project] = []
    public private(set) var chats: [Chat] = []
    public private(set) var openChatIDs: [UUID] = []
    public var selectedChatID: UUID?
    /// The reply being written right now, per chat. Saved as a message when the turn ends.
    public private(set) var live: [UUID: [Part]] = [:]
    /// Set when xBot cannot save, so the window can say so instead of pretending.
    public var problem: String?

    private var brains: [HarnessKind: any Brain] = [:]
    private var transcripts: [UUID: [ChatMessage]] = [:]
    private var turns: [UUID: Task<Void, Never>] = [:]
    private let store: Store
    private let inbox: URL
    private let discover: @Sendable () async -> [HarnessKind: any Brain]

    public init(
        store: Store,
        inbox: URL,
        discover: @escaping @Sendable () async -> [HarnessKind: any Brain]
    ) {
        self.store = store
        self.inbox = inbox
        self.discover = discover
        projects = attempt { try store.projects() } ?? []
        chats = attempt { try store.chats() } ?? []
    }

    public var availableHarnesses: [HarnessKind] { HarnessKind.allCases.filter { brains[$0] != nil } }

    public func refreshHarnesses() async {
        brains = await discover()
    }

    public func chat(_ id: UUID) -> Chat? { chats.first { $0.id == id } }

    public func messages(in id: UUID) -> [ChatMessage] { transcripts[id] ?? [] }

    public func isRunning(_ id: UUID) -> Bool { turns[id] != nil }

    /// Why the composer cannot send, in a sentence, or nil when it can. A running turn is not a
    /// reason: the composer shows Stop instead.
    public func sendBlockedReason(_ id: UUID) -> String? {
        guard let chat = chat(id) else { return nil }
        if brains[chat.harness] == nil {
            return String(localized: "\(chat.harness.displayName) isn't installed on this Mac any more.")
        }
        return nil
    }

    // MARK: Projects

    @discardableResult
    public func addProject(at url: URL) -> Project {
        let path = url.standardizedFileURL.path(percentEncoded: false)
            .trimmingSuffix("/")
        if let existing = projects.first(where: { $0.path == path }) { return existing }
        let project = Project(name: URL(filePath: path).lastPathComponent, path: path)
        attempt { try store.save(project) }
        projects = attempt { try store.projects() } ?? projects + [project]
        return project
    }

    /// Forgets the project and its chats. The folder itself is not touched.
    public func removeProject(_ id: UUID) {
        for chat in chats where chat.projectID == id { stop(chat.id); forget(chat.id) }
        attempt { try store.deleteProject(id) }
        projects.removeAll { $0.id == id }
        chats.removeAll { $0.projectID == id }
    }

    // MARK: Chats

    /// A new chat with the harness used most recently, or nil when no harness is installed.
    @discardableResult
    public func newChat(in projectID: UUID?) -> Chat? {
        let recent = chats.first.map(\.harness).flatMap { brains[$0] == nil ? nil : $0 }
        guard let harness = recent ?? availableHarnesses.first else { return nil }
        let chat = Chat(projectID: projectID, title: String(localized: "New chat"), harness: harness, mode: .editFiles)
        attempt { try store.save(chat) }
        chats.insert(chat, at: 0)
        transcripts[chat.id] = []
        open(chat.id)
        return chat
    }

    public func open(_ id: UUID) {
        if transcripts[id] == nil { transcripts[id] = attempt { try store.messages(in: id) } ?? [] }
        if !openChatIDs.contains(id) { openChatIDs.append(id) }
        selectedChatID = id
    }

    /// Closes the tab. A running turn keeps going; the chat is still in the sidebar.
    public func close(_ id: UUID) {
        guard let index = openChatIDs.firstIndex(of: id) else { return }
        openChatIDs.remove(at: index)
        if selectedChatID == id {
            selectedChatID = openChatIDs.indices.contains(index) ? openChatIDs[index] : openChatIDs.last
        }
    }

    public func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.title = trimmed }
    }

    public func deleteChat(_ id: UUID) {
        stop(id)
        attempt { try store.deleteChat(id) }
        chats.removeAll { $0.id == id }
        forget(id)
    }

    public func setHarness(_ kind: HarnessKind, for id: UUID) {
        // A session id means nothing to a different CLI, and neither does its model name.
        update(id) { $0.harness = kind; $0.sessionID = nil; $0.model = nil }
    }

    public func setModel(_ model: String?, for id: UUID) { update(id) { $0.model = model } }

    public func setMode(_ mode: PermissionMode, for id: UUID) { update(id) { $0.mode = mode } }

    // MARK: Turns

    /// Starts a turn. False, with nothing changed, when the chat is busy or cannot send — so the
    /// composer keeps what was typed.
    @discardableResult
    public func send(_ text: String, in id: UUID) -> Bool {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isRunning(id), var chat = chat(id), let brain = brains[chat.harness] else {
            return false
        }

        save(ChatMessage(chatID: id, role: .user, parts: [.text(prompt)]))
        if chat.title == String(localized: "New chat") { chat.title = Self.title(from: prompt) }
        chat.updatedAt = .now
        replace(chat)

        let request = TurnRequest(
            prompt: prompt, directory: directory(for: chat), model: chat.model,
            mode: chat.mode, resumeID: chat.sessionID
        )
        live[id] = []
        turns[id] = Task { [weak self] in
            for await event in brain.run(request) {
                self?.receive(event, in: id)
            }
            self?.end(id, stopped: false)
        }
        return true
    }

    public func stop(_ id: UUID) {
        let task = turns[id]
        end(id, stopped: true)
        task?.cancel()
    }

    /// Saves every reply in progress and stops its CLI. Called when the app quits.
    public func stopAll() {
        for id in Array(turns.keys) { stop(id) }
    }

    public static func title(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 48 ? String(trimmed.prefix(48)) + "…" : trimmed
    }

    // MARK: Private

    private func receive(_ event: BrainEvent, in id: UUID) {
        guard turns[id] != nil else { return }
        if case .session(let session) = event {
            update(id) { $0.sessionID = session }
            return
        }
        live[id, default: []].apply(event)
    }

    /// Ends a turn once: whichever of stop and the stream finishing comes first saves the reply.
    private func end(_ id: UUID, stopped: Bool) {
        guard turns.removeValue(forKey: id) != nil else { return }
        var parts = live.removeValue(forKey: id) ?? []
        if stopped { parts.append(.notice(String(localized: "Stopped."))) }
        if !parts.isEmpty { save(ChatMessage(chatID: id, role: .assistant, parts: parts)) }
        update(id) { $0.updatedAt = .now }
    }

    private func directory(for chat: Chat) -> URL {
        if let projectID = chat.projectID, let project = projects.first(where: { $0.id == projectID }) {
            return project.url
        }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    private func save(_ message: ChatMessage) {
        attempt { try store.append(message) }
        transcripts[message.chatID, default: []].append(message)
    }

    private func update(_ id: UUID, _ change: (inout Chat) -> Void) {
        guard var chat = chat(id) else { return }
        change(&chat)
        replace(chat)
    }

    private func replace(_ chat: Chat) {
        attempt { try store.save(chat) }
        if let index = chats.firstIndex(where: { $0.id == chat.id }) { chats[index] = chat }
        chats.sort { $0.updatedAt > $1.updatedAt }
    }

    private func forget(_ id: UUID) {
        transcripts[id] = nil
        close(id)
    }

    /// Runs a store call; a failure becomes `problem` rather than a crash or a silent loss.
    @discardableResult
    private func attempt<T>(_ body: () throws -> T) -> T? {
        do { return try body() } catch {
            problem = String(localized: "xBot couldn't save to its library: \(String(describing: error))")
            return nil
        }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        count > 1 && hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
```

- [ ] **Step 4: Run** `swift test --filter WorkspaceTests` ten times → PASS every time.
- [ ] **Step 5: Commit** — `"The workspace: projects, chats, and turns that save as they end."`

---

### Task 8: The window

**Files:**
- Create: `apps/mac/Sources/XBotUI/Shell/RootView.swift`, `apps/mac/Sources/XBotUI/Shell/Sidebar.swift`, `apps/mac/Sources/XBotUI/Shell/EmptyState.swift`, `apps/mac/Sources/XBotUI/Chat/ChatTabs.swift`, `apps/mac/Sources/XBotUI/Chat/ChatView.swift`, `apps/mac/Sources/XBotUI/Chat/MessageView.swift`, `apps/mac/Sources/XBotUI/Chat/ChatComposer.swift`
- Modify: `apps/mac/Sources/XBotUI/DesignSystem/Space.swift` (add `Metrics.sidebarWidth`, `Metrics.readingWidth`, `Metrics.defaultWindow`; remove `railWidth`, `panelWidth`, `onboardingWindow`, `bubbleMaximumWidthFraction` if nothing uses them)
- Modify: `apps/mac/Sources/XBotApp/XBotApp.swift`
- Create: `apps/mac/Sources/XBotApp/AppDelegate.swift`

**Interfaces:**
- Consumes: everything `Workspace` produces (Task 7).
- Produces: `public struct RootView: View { public init(workspace: Workspace) }`.

Views render state and send intents; no logic beyond formatting. No unit tests (per CLAUDE.md); verification is building and running the app.

- [ ] **Step 1: Tokens** — in `Space.swift`'s `Metrics`:

```swift
public enum Metrics {
    public static let sidebarWidth: ClosedRange<CGFloat> = 220...360
    public static let sidebarIdealWidth: CGFloat = 260
    /// A transcript line longer than this is hard to read; wider windows add margin, not width.
    public static let readingWidth: CGFloat = 760
    public static let minimumWindow = CGSize(width: 900, height: 600)
    public static let defaultWindow = CGSize(width: 1280, height: 820)
    public static let titleBarHeight: CGFloat = 52
    public static let tabWidth: CGFloat = 200
}
```

- [ ] **Step 2: `RootView.swift`**

```swift
import SwiftUI
import XBotCore

/// The window: projects and chats on the left, the open chats on the right.
public struct RootView: View {
    @Bindable private var workspace: Workspace
    @State private var addingProject = false

    public init(workspace: Workspace) { self.workspace = workspace }

    public var body: some View {
        NavigationSplitView {
            Sidebar(workspace: workspace, addProject: { addingProject = true })
                .navigationSplitViewColumnWidth(
                    min: Metrics.sidebarWidth.lowerBound,
                    ideal: Metrics.sidebarIdealWidth,
                    max: Metrics.sidebarWidth.upperBound
                )
        } detail: {
            VStack(spacing: 0) {
                if let problem = workspace.problem {
                    Text(problem)
                        .captionText()
                        .foregroundStyle(Palette.stateFailed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.s)
                        .background(Palette.panelBackground)
                }
                if let id = workspace.selectedChatID, let chat = workspace.chat(id) {
                    ChatTabs(workspace: workspace)
                    ChatView(workspace: workspace, chat: chat).id(chat.id)
                } else {
                    EmptyState(workspace: workspace, addProject: { addingProject = true })
                }
            }
            .background(Palette.windowBackground)
        }
        .fileImporter(isPresented: $addingProject, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let project = workspace.addProject(at: url)
                workspace.newChat(in: project.id)
            }
        }
        .task { await workspace.refreshHarnesses() }
    }
}
```

- [ ] **Step 3: `Sidebar.swift`**

```swift
import SwiftUI
import XBotCore

struct Sidebar: View {
    let workspace: Workspace
    let addProject: () -> Void
    @State private var pendingDelete: Chat?

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(chats(in: nil)) { row($0) }
            } header: {
                header(String(localized: "Inbox"), systemImage: "tray", project: nil)
            }
            ForEach(workspace.projects) { project in
                Section {
                    ForEach(chats(in: project.id)) { row($0) }
                } header: {
                    header(project.name, systemImage: "folder", project: project.id)
                        .contextMenu {
                            Button(String(localized: "Show in Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([project.url])
                            }
                            Button(String(localized: "Remove from xBot")) { workspace.removeProject(project.id) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button(action: addProject) {
                    Label(String(localized: "Add Project"), systemImage: "folder.badge.plus")
                }
                .help(String(localized: "Add a folder to work in"))
            }
        }
        .confirmationDialog(
            String(localized: "Delete this chat?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { chat in
            Button(String(localized: "Delete Chat"), role: .destructive) { workspace.deleteChat(chat.id) }
        } message: { _ in
            Text(String(localized: "The conversation is removed from xBot. Files the agent changed stay as they are."))
        }
    }

    private var selection: Binding<UUID?> {
        Binding(get: { workspace.selectedChatID }, set: { if let id = $0 { workspace.open(id) } })
    }

    private func chats(in project: UUID?) -> [Chat] {
        workspace.chats.filter { $0.projectID == project }
    }

    private func header(_ title: String, systemImage: String, project: UUID?) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Button { workspace.newChat(in: project) } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless)
                .help(String(localized: "New chat"))
                .disabled(workspace.availableHarnesses.isEmpty)
        }
    }

    private func row(_ chat: Chat) -> some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(chat.title).bodyText().lineLimit(1)
                Text(chat.harness.displayName).captionText().foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if workspace.isRunning(chat.id) {
                ProgressView().controlSize(.small)
            } else {
                Text(chat.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .captionText()
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .tag(chat.id)
        .contextMenu {
            Button(String(localized: "Delete Chat…"), role: .destructive) { pendingDelete = chat }
        }
    }
}
```

- [ ] **Step 4: `EmptyState.swift`** — the honest states: no agent installed, or nothing open.

```swift
import SwiftUI
import XBotCore

struct EmptyState: View {
    let workspace: Workspace
    let addProject: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            AppMark()
            if workspace.availableHarnesses.isEmpty {
                Text(String(localized: "xBot works through an AI agent you already have."))
                    .sectionTitle()
                Text(String(localized: "Install Claude Code or Codex and sign in, then come back. xBot will find it."))
                    .bodyText()
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: Space.m) {
                    Link(String(localized: "Get Claude Code"), destination: URL(string: "https://claude.com/product/claude-code")!)
                    Link(String(localized: "Get Codex"), destination: URL(string: "https://developers.openai.com/codex")!)
                }
                Button(String(localized: "Look Again")) { Task { await workspace.refreshHarnesses() } }
                    .buttonStyle(.borderedProminent)
            } else {
                Text(String(localized: "What are we working on?")).sectionTitle()
                HStack(spacing: Space.m) {
                    Button(String(localized: "New Chat")) { workspace.newChat(in: nil) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("n", modifiers: .command)
                    Button(String(localized: "Add a Project Folder…"), action: addProject)
                }
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```
(Read `Components/AppMark.swift` first; if its initialiser takes arguments, pass the size token it expects.)

- [ ] **Step 5: `ChatTabs.swift`**

```swift
import SwiftUI
import XBotCore

/// Open chats as tabs. Closing a tab does not stop its turn or delete it.
struct ChatTabs: View {
    let workspace: Workspace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                ForEach(workspace.openChatIDs, id: \.self) { id in
                    if let chat = workspace.chat(id) { tab(chat) }
                }
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
        }
        .background(Palette.panelBackground)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tab(_ chat: Chat) -> some View {
        let selected = workspace.selectedChatID == chat.id
        return HStack(spacing: Space.xs) {
            if workspace.isRunning(chat.id) { ProgressView().controlSize(.mini) }
            Text(chat.title).captionText().lineLimit(1)
            Spacer(minLength: Space.xs)
            Button { workspace.close(chat.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(String(localized: "Close tab"))
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .frame(width: Metrics.tabWidth)
        .background(
            selected ? Palette.elevatedSurface : .clear,
            in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture { workspace.open(chat.id) }
        .motion(Motion.quick, value: selected)
    }
}
```

- [ ] **Step 6: `MessageView.swift`**

```swift
import SwiftUI
import XBotCore

/// One message: the person's on the right as they typed it, the agent's on the left, rendered.
struct MessageView: View {
    let role: Role
    let parts: [Part]
    var isLive = false

    var body: some View {
        if role == .user {
            Text(userText)
                .bodyText()
                .textSelection(.enabled)
                .foregroundStyle(Palette.bubbleOutgoingText)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .background(Palette.bubbleOutgoing, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .text(let text): ReplyText(text: text)
                    case .tool(let tool): ToolRow(tool: tool)
                    case .notice(let text):
                        Text(text).captionText().foregroundStyle(Palette.textTertiary)
                    case .failure(let reason):
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .captionText()
                            .foregroundStyle(Palette.stateFailed)
                            .textSelection(.enabled)
                    }
                }
                if isLive { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var userText: String {
        parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n")
    }
}

private struct ReplyText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(MessageMarkdown.blocks(of: text)) { block in
                switch block {
                case .prose(let prose):
                    Text(MessageMarkdown.inline(prose)).bodyText().textSelection(.enabled)
                case .code(let code, let language):
                    CodeBlockView(code: code, language: language)
                }
            }
        }
        .foregroundStyle(Palette.textPrimary)
    }
}

/// A tool call, one line; its output on request.
private struct ToolRow: View {
    let tool: ToolPart
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button { expanded.toggle() } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: icon).foregroundStyle(tool.isError ? Palette.stateFailed : Palette.textSecondary)
                    Text(tool.name).captionText().bold()
                    Text(tool.summary).captionText().foregroundStyle(Palette.textSecondary).lineLimit(1)
                    if tool.output == nil { ProgressView().controlSize(.mini) }
                }
            }
            .buttonStyle(.plain)
            .disabled((tool.output ?? "").isEmpty)
            if expanded, let output = tool.output, !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(Typography.mono)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: Metrics.toolOutputMaxHeight)
                .padding(Space.s)
                .background(Palette.codeBackground, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            }
        }
        .motion(Motion.quick, value: expanded)
    }

    private var icon: String {
        if tool.isError { return "exclamationmark.circle" }
        return tool.output == nil ? "circle.dotted" : "checkmark.circle"
    }
}
```
Add `public static let toolOutputMaxHeight: CGFloat = 240` to `Metrics`. If `CodeBlockView`'s initialiser differs, match it.

- [ ] **Step 7: `ChatComposer.swift`**

```swift
import SwiftUI
import XBotBrain
import XBotCore

/// The input. ⏎ sends; ⌥⏎ is a new line. The agent, model and permission chips sit under it.
struct ChatComposer: View {
    let workspace: Workspace
    let chat: Chat
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            TextField(String(localized: "Ask, build, plan…"), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .bodyText()
                .lineLimit(1...8)
                .focused($focused)
                .onSubmit(send)
            HStack(spacing: Space.s) {
                Menu(chat.harness.displayName) {
                    ForEach(workspace.availableHarnesses, id: \.self) { kind in
                        Button(kind.displayName) { workspace.setHarness(kind, for: chat.id) }
                    }
                }
                .fixedSize()
                if chat.harness.models.count > 1 {
                    Menu(chat.model ?? String(localized: "Default model")) {
                        ForEach(chat.harness.models, id: \.self) { model in
                            Button(model ?? String(localized: "Default model")) { workspace.setModel(model, for: chat.id) }
                        }
                    }
                    .fixedSize()
                }
                Menu {
                    ForEach(PermissionMode.allCases, id: \.self) { mode in
                        Button { workspace.setMode(mode, for: chat.id) } label: {
                            Label(mode.title, systemImage: mode.symbol)
                        }
                    }
                } label: {
                    Label(chat.mode.title, systemImage: chat.mode.symbol)
                }
                .fixedSize()
                Spacer()
                if let reason = workspace.sendBlockedReason(chat.id) {
                    Text(reason).captionText().foregroundStyle(Palette.textSecondary)
                }
                if workspace.isRunning(chat.id) {
                    Button { workspace.stop(chat.id) } label: { Image(systemName: "stop.circle.fill") }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(".", modifiers: .command)
                        .help(String(localized: "Stop"))
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill") }
                        .buttonStyle(.borderless)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || workspace.sendBlockedReason(chat.id) != nil)
                        .help(String(localized: "Send"))
                }
            }
            .controlSize(.small)
            .menuStyle(.borderlessButton)
        }
        .padding(Space.m)
        .background(Palette.elevatedSurface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.separator))
        .padding(Space.l)
        .frame(maxWidth: Metrics.readingWidth)
        .onAppear { focused = true }
    }

    private func send() {
        // Cleared only when the workspace took it: a refused send keeps what was typed.
        if workspace.send(text, in: chat.id) { text = "" }
    }
}

extension PermissionMode {
    var title: String {
        switch self {
        case .readOnly: String(localized: "Read only")
        case .editFiles: String(localized: "Can edit")
        case .fullAccess: String(localized: "Full access")
        }
    }

    var symbol: String {
        switch self {
        case .readOnly: "eye"
        case .editFiles: "pencil"
        case .fullAccess: "bolt"
        }
    }
}
```
`XBotUI` needs `XBotBrain` visible: add `"XBotBrain"` to `XBotUI`'s dependencies in `Package.swift`, or re-export from `XBotCore` with `@_exported import XBotBrain` in `Models.swift`. Use the re-export — one line, and every `XBotCore` client needs these types anyway.

- [ ] **Step 8: `ChatView.swift`**

```swift
import SwiftUI
import XBotCore

struct ChatView: View {
    let workspace: Workspace
    let chat: Chat

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xl) {
                    ForEach(workspace.messages(in: chat.id)) { message in
                        MessageView(role: message.role, parts: message.parts)
                    }
                    if let live = workspace.live[chat.id] {
                        MessageView(role: .assistant, parts: live, isLive: true)
                    }
                }
                .padding(Space.xl)
                .frame(maxWidth: Metrics.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            ChatComposer(workspace: workspace, chat: chat)
        }
        .navigationTitle(chat.title)
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        chat.projectID.flatMap { id in workspace.projects.first { $0.id == id }?.path }
            ?? String(localized: "Inbox")
    }
}
```

- [ ] **Step 9: `AppDelegate.swift` and `XBotApp.swift`**

```swift
import AppKit
import XBotCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var workspace: Workspace?

    /// A bare executable (`swift run`) has no Info.plist and can be handed the prohibited
    /// activation policy: the window draws but never takes keystrokes. The bundled app never
    /// takes this branch.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard Bundle.main.bundleIdentifier == nil else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Saves every reply in progress and stops the CLIs writing them.
    func applicationWillTerminate(_ notification: Notification) {
        Self.workspace?.stopAll()
    }
}
```

```swift
import AppKit
import SwiftUI
import XBotBrain
import XBotCore
import XBotUI

@main
struct XBotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let appUpdates = SparkleAppUpdateController()
    @State private var workspace = Self.makeWorkspace()

    var body: some Scene {
        Window("xBot", id: "main") {
            RootView(workspace: workspace)
                .frame(minWidth: Metrics.minimumWindow.width, minHeight: Metrics.minimumWindow.height)
        }
        .defaultSize(Metrics.defaultWindow)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "About xBot")) { AboutPanel.show() }
            }
            CommandGroup(after: .appInfo) {
                Button(String(localized: "Check for Updates…")) { appUpdates.checkForUpdates(userInitiated: true) }
            }
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "New Chat")) { workspace.newChat(in: nil) }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(workspace.availableHarnesses.isEmpty)
                Button(String(localized: "Close Tab")) {
                    if let id = workspace.selectedChatID { workspace.close(id) }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(workspace.selectedChatID == nil)
            }
            CommandGroup(replacing: .help) {
                Button(String(localized: "xBot Documentation")) { NSWorkspace.shared.open(AboutPanel.documentationURL) }
            }
        }
    }

    /// The library on disk, or — if it cannot be opened — one in memory with the reason on screen,
    /// so the app still works and says plainly that nothing will be kept.
    @MainActor
    private static func makeWorkspace() -> Workspace {
        let inbox = Store.supportDirectory.appending(path: "Inbox", directoryHint: .isDirectory)
        let discover: @Sendable () async -> [HarnessKind: any Brain] = { await HarnessLocator.installed() }
        let workspace: Workspace
        do {
            workspace = Workspace(store: try Store.live(), inbox: inbox, discover: discover)
        } catch {
            workspace = Workspace(store: .inMemory(), inbox: inbox, discover: discover)
            workspace.problem = String(
                localized: "xBot couldn't open its library, so this session won't be saved. \(String(describing: error))"
            )
        }
        AppDelegate.workspace = workspace
        return workspace
    }
}
```
`Metrics` lives in `XBotUI`; it is already public.

- [ ] **Step 10: Build, test, run.**

Run: `cd apps/mac && swift build --build-tests && swift test`
Expected: all suites pass.

Then `swift run XBot`, and check by hand:
1. With Claude Code installed, the empty state offers New Chat. ⌘N opens a chat; "Reply with one word" streams a reply; the sidebar row shows a spinner and then a time.
2. Add Project → choose a folder → a chat opens titled "New chat" with the folder path as subtitle; "list the files here" shows a tool row whose output expands.
3. A long-running prompt → ⌘. stops it; the partial reply shows "Stopped."; quit and relaunch → both chats and their messages are there.
4. Switch the chip to Codex and send → Codex answers.

- [ ] **Step 11: Commit** — `"The window: projects, chat tabs, transcript and composer."`

---

### Task 9: Remove the engine, and make the docs tell the truth

**Files:**
- Delete: `engine/`, `scripts/build-engine-image.sh`, `scripts/build-engine-manifest.py`, `scripts/check-engine-health.sh`, `scripts/dev-db.sh`, `scripts/engine-manifest.template.json`, `scripts/generate-engine-manifest.sh`, `scripts/read-health-field.py`, `scripts/README-engine-manifest.md`, `scripts/verify-m5-handoff.sh`, `.github/workflows/engine-image.yml`, `docs/03-openbot-fork.md`, `docs/07-container-runtime.md`, `docs/env-mapping.md`
- Modify: `.github/workflows/ci.yml` (remove `engine-static`, `engine-test`; the `mac` job runs `swift build --build-tests` then `swift test`), `.github/workflows/mac-release.yml` (remove engine steps, if any), `scripts/uninstall-xbot.command` (read first; drop Docker/Colima steps, keep removing `~/Library/Application Support/xBot`)
- Modify: `docs/decisions/0001-…`, `0003-…`, `0007-…`, `0008-…` — status line `Superseded by 0009` at the top; content kept
- Create: `docs/decisions/0009-native-harness-redesign.md`
- Rewrite: `CLAUDE.md`, `docs/02-architecture.md`, `docs/05-mac-app.md`
- Modify: `docs/04-model-providers.md`, `docs/06-onboarding.md`, `docs/09-ui-spec.md`, `docs/12-roadmap.md` — a banner at the top: describes the pre-redesign app; rewritten in the sub-project named in the spec's build order
- Modify: `NOTICE`, `CHANGELOG.md`, `apps/mac/Sources/XBotUI/AboutPanel.swift`, `apps/mac/Tests/XBotUITests/AboutCreditTests.swift`
- Modify: `docs/superpowers/specs/2026-10-06-xbot-redesign-design.md` — build order (cleanup moved first), projects stored as paths (the app is not sandboxed, so no bookmarks)
- Do not touch `README.md`.

- [ ] **Step 1: Delete** the engine and its scripts with `git rm -r`. `grep -rn "engine\|docker\|colima" scripts .github` and fix whatever still refers to them.

- [ ] **Step 2: ADR 0009** — context (Docker + OpenBot + CopilotKit runner was heavy, needed a container runtime, and duplicated agents the person already has), decision (native Swift app driving installed agent CLIs; native loop later; Apple Containerization per bot; SQLite), consequences (macOS 26 / Apple silicon floor; no listening ports; harness formats are a moving target, mitigated with fixtures; OpenBot code no longer ships).

- [ ] **Step 3: Credits.** `NOTICE`: credit MonoCode (hardbeat920/monocode, MIT) for the design the app follows, and record that xBot 1.x was built on OpenBot (© 2026 CopilotKit, MIT). The About panel says the same, with both links. Update `AboutCreditTests` to expect both names and both links. `CHANGELOG.md`: an `Unreleased` entry — the engine removed, the new shell, and the OpenBot credit history.

- [ ] **Step 4: `CLAUDE.md`** — rewrite for the new architecture: what xBot is now; the module graph; the harness contract (prompt on stdin, one terminal event, fixtures from real runs); the invariants from the spec, including "no listening ports"; the verification commands without the engine; keep the working agreements, the Swift/SwiftUI conventions, the motion rules and the parallel-suites warning, which all still apply.

- [ ] **Step 5: Verify**

Run: `cd apps/mac && swift build --build-tests && swift test` and `grep -rn "XBotEngine\|XBotRuntime\|docker" apps/mac/Sources apps/mac/Tests` (expect nothing).

- [ ] **Step 6: Commit** — `"Remove the OpenBot engine; docs describe the app that exists."`

---

## After this plan

Next plan (sub-project 1b): split panes, per-turn checkpoints with Undo All / Keep All, worktrees for git projects, the Changes inspector. Then notes, bots, the native brain, the machine, the browser, licensing — in the spec's order.
