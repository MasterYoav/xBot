# Workspace panels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A transparent top bar; a right inspector with the project's git state, everyday git actions and a file explorer; an account menu with live usage; a ChatGPT-style profile page built from the person's agent history; a Settings window.

**Architecture:** Logic lives in `XBotBrain` (rate-limit parsing — Foundation only) and `XBotCore` (git runner and parsers, the project git model, the explorer tree, usage storage, the history indexer and profile maths), all tested without a window. `XBotUI` renders it: `Inspector/`, `Account/`, `Profile/`, `Settings/`. Git and gh run as processes; the file watcher is FSEvents; the history index is its own SQLite file owned by an actor.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI on macOS 26, Swift Testing, system SQLite3, FSEvents, Collaboration (account picture), QuickLook (`quickLookPreview`). No new packages.

**Spec:** `docs/superpowers/specs/2026-10-08-workspace-panels-design.md`

## Global Constraints

- Swift 6 language mode; `@MainActor @Observable` for models the window reads; actors for background work.
- Every user-facing string through `String(localized:)`; design tokens only (no raw hex, sizes or durations in views).
- No credentials read: never `~/.codex/auth.json`, never the Keychain. `~/.claude.json` is read only for `oauthAccount.organizationType`.
- Nothing leaves the Mac: no network calls except `git fetch/pull/push` and `gh` the person already configured.
- No terminal instructions in the product. Git failures show git's own stderr in the panel.
- Discard is confirmed once (not undoable); Move to Trash is not confirmed (recoverable).
- Log out does not appear in this plan (Apple ID work).
- Tests that touch `UserDefaults` inject a suite (`UserDefaults(suiteName: UUID().uuidString)`), never `.standard`.
- Verify with `cd apps/mac && swift build --build-tests && swift test` before claiming anything works.

## Review Focus

1. **Claude transcripts repeat one message's usage on several lines** (one per content block, same `message.id`) — tokens must be counted once per message, or the profile triples every number. (Task 9 test `aMessageSplitAcrossLinesCountsOnce`.)
2. **A log line half-written when the indexer reads** — it must not be consumed; the next pass reads it whole. (Task 9 test `aPartialLastLineWaitsForTheNextPass`.)
3. **Push or fetch that needs a password with no terminal** — must fail with git's message, never hang. `GIT_TERMINAL_PROMPT=0` and ssh `BatchMode=yes`; `git status` must not write the index (`GIT_OPTIONAL_LOCKS=0`) or the watcher feeds itself. (Task 3 test `gitNeverPromptsOrLocks`.)
4. **Paths with spaces, renames and conflicts in porcelain v2** — parsed into the right file, original path and letter. (Task 3 tests `pathsWithSpacesAndRenames`, `conflictsAreConflicts`.)
5. **Diff of an untracked file** — `git diff --no-index` exits 1 when there are differences; that is the diff, shown as all added, not an error. (Task 5 test `anUntrackedFileDiffsAsAllAdded`.)

---

## File map

| File | Responsibility |
| --- | --- |
| `XBotBrain/RateLimits.swift` (new) | `RateWindow`, `RateLimits`; Codex rollout reader; Claude plan name from `~/.claude.json` |
| `XBotBrain/BrainEvent.swift` | `case limits(RateLimits)` |
| `XBotBrain/ClaudeStream.swift` | `rate_limit_event` → `.limits` |
| `XBotCore/Usage.swift` (new) | `AgentUsage`, `UsageText` formatting |
| `XBotCore/Store.swift` | v3: `usage` table; `planRuns()` |
| `XBotCore/Workspace+Panels.swift` (new) | usage recording, event wrapper, profile/diff page state, mention, ask-to-merge, git models, draft defaults |
| `XBotCore/Git/GitTool.swift` (new) | find git/gh; run a process; the git environment |
| `XBotCore/Git/GitStatus.swift` (new) | porcelain v2 parser, `GitState`, numstat totals |
| `XBotCore/Git/PullRequest.swift` (new) | GitHub slug from a remote URL; `gh pr view` JSON |
| `XBotCore/Git/UnifiedDiff.swift` (new) | unified diff → numbered lines |
| `XBotCore/Git/ProjectGit.swift` (new) | per-project observable git model and its actions |
| `XBotCore/Git/FolderWatcher.swift` (new) | FSEvents, 300 ms latency |
| `XBotCore/FileTree.swift` (new) | explorer listing, git colours, mention text |
| `XBotCore/History/HistoryTally.swift` (new) | pure per-line accounting of Claude and Codex logs |
| `XBotCore/History/HistoryIndexer.swift` (new) | actor: incremental file reads into `history.sqlite`; summary |
| `XBotCore/History/ProfileStats.swift` (new) | lifetime, peak, streaks, heatmap |
| `XBotUI/Shell/TopBar.swift`, `RootView.swift`, `Sidebar.swift` | transparent strip; inspector; account footer |
| `XBotUI/Inspector/*.swift` (new) | `InspectorView`, `ChangesPanel`, `ExplorerPanel`, `FileIcon`, `DiffView` |
| `XBotUI/Account/*.swift` (new) | `Identity`, `AccountButton` + popover, `UsageSection` |
| `XBotUI/Profile/*.swift` (new) | `ProfileView`, `Heatmap`, `EditProfileSheet` |
| `XBotUI/Settings/SettingsView.swift` (new) | General / Agents / About |
| `XBotApp/XBotApp.swift` | `Settings` scene, ⌥⌘0, indexer at launch |

---

### Task 1: Transparent top bar and the inspector toggle

**Files:**
- Modify: `apps/mac/Sources/XBotUI/Shell/TopBar.swift`, `apps/mac/Sources/XBotUI/Shell/RootView.swift`, `apps/mac/Sources/XBotUI/DesignSystem/Palette.swift`, `apps/mac/Sources/XBotUI/DesignSystem/Space.swift`

**Interfaces:**
- Produces: `TopBar(workspace:sidebarVisible:showSidebar:inspectorShown: Binding<Bool>, inspectorAvailable: Bool)`; `@AppStorage("inspectorShown")` key shared with the app's ⌥⌘0 command; `Metrics.inspectorWidth: ClosedRange<CGFloat> = 260...420`, `Metrics.inspectorIdealWidth: CGFloat = 300`; `Palette.tabSelected`.

- [ ] **Step 1:** Palette: delete `tabStrip`; add
  ```swift
  /// The selected tab: a soft translucent segment over the backdrop.
  public static let tabSelected = dynamic(0xFFFFFF, 0xFFFFFF, alpha: (0.6, 0.1))
  ```
  Metrics: add `inspectorWidth`, `inspectorIdealWidth` as above.
- [ ] **Step 2:** TopBar: remove the `.background(alignment: .bottom)` block and each tab's trailing hairline. Selected tab background becomes `RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(selected ? Palette.tabSelected : (hovering ? Palette.hover : .clear))` with `.padding(.vertical, Space.xs)`. Replace the trailing `MonoLabel(context…)` with
  ```swift
  IconButton("sidebar.right", help: inspectorAvailable
      ? String(localized: "Show files and changes (⌥⌘0)")
      : String(localized: "Choose a project to see its files and changes.")) { inspectorShown.toggle() }
      .disabled(!inspectorAvailable)
      .padding(.trailing, Space.s)
  ```
  and delete `context(for:)`.
- [ ] **Step 3:** RootView: the detail becomes `ZStack(alignment: .top) { Backdrop(...); VStack(spacing: 0) { TopBar(...); problem banner; page } }` so the backdrop runs behind the tabs; `.background(Palette.window)` stays on the ZStack. Add
  ```swift
  @AppStorage("inspectorShown") private var inspectorShown = false
  private var inspectorProject: Project? { workspace.contextProject }
  ```
  and on the detail `.inspector(isPresented: Binding(get: { inspectorShown && inspectorProject != nil }, set: { inspectorShown = $0 })) { if let project = inspectorProject { InspectorView(workspace: workspace, project: project).inspectorColumnWidth(min: Metrics.inspectorWidth.lowerBound, ideal: Metrics.inspectorIdealWidth, max: Metrics.inspectorWidth.upperBound) } }`. (`InspectorView` arrives in Task 6; until then a `Text(project.name)` placeholder view in `Inspector/InspectorView.swift` keeps the build green.)
  `workspace.contextProject` is defined in Task 2 (`Workspace+Panels.swift`); add it now:
  ```swift
  /// The project the window is about: the open chat's, or Home's draft's.
  public var contextProject: Project? {
      let id = selectedChatID.flatMap { chat($0)?.projectID } ?? (isHome ? draft.projectID : nil)
      return id.flatMap { id in projects.first { $0.id == id } }
  }
  ```
- [ ] **Step 4:** `swift build --build-tests` → succeeds. Snapshot the real window: `XBOT_WINDOW_SNAPSHOT=/tmp/top.png .build/debug/XBot` and look: no grey band, the sunset runs under the tabs, lights visible.
- [ ] **Step 5:** Commit `Top bar: no strip; the sunset runs under the tabs; the inspector toggle.`

### Task 2: Rate limits — parse, store, show where they come from

**Files:**
- Create: `apps/mac/Sources/XBotBrain/RateLimits.swift`, `apps/mac/Sources/XBotCore/Usage.swift`, `apps/mac/Sources/XBotCore/Workspace+Panels.swift`
- Modify: `BrainEvent.swift`, `ClaudeStream.swift`, `Models.swift` (`apply` ignores `.limits`), `Workspace+Plan.swift` (`drivePlanning` switch), `Workspace.swift` (init params; `brain.run` → `events`), `Store.swift` (v3)
- Test: `apps/mac/Tests/XBotBrainTests/RateLimitsTests.swift`, `apps/mac/Tests/XBotCoreTests/UsageTests.swift`

**Interfaces:**
- Produces (XBotBrain):
  ```swift
  public struct RateWindow: Codable, Equatable, Sendable { public var usedPercent: Double; public var resetsAt: Date }
  public struct RateLimits: Codable, Equatable, Sendable { public var fiveHour: RateWindow?; public var weekly: RateWindow?; public var plan: String? }
  case limits(RateLimits)   // BrainEvent
  public enum CodexUsage { static func limits(fromLine: String) -> RateLimits?; public static func latest(in sessions: URL = default) -> RateLimits?; static func planName(_ type: String) -> String? }
  public enum ClaudeAccount { public static func plan(at url: URL = ~/.claude.json) -> String? }
  ```
- Produces (XBotCore): `AgentUsage { agent, limits, updatedAt }`; `Workspace.usage: [HarnessKind: AgentUsage]`; `Workspace.refreshCodexUsage() async`; `UsageText.remaining(_:)`, `.resets(_:now:calendar:locale:)`, `.updated(_:now:)`.

- [ ] **Step 1: Failing tests** `RateLimitsTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import XBotBrain

  @Suite struct RateLimitsTests {
      @Test func claudeReportsBothWindows() {
          let line = #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","unifiedWindows":{"five_hour":{"utilization":0.55,"resetsAt":1791495000},"seven_day":{"utilization":0.11,"resetsAt":1791658800}}}}"#
          #expect(ClaudeStream.events(from: line) == [.limits(RateLimits(
              fiveHour: RateWindow(usedPercent: 55, resetsAt: Date(timeIntervalSince1970: 1791495000)),
              weekly: RateWindow(usedPercent: 11, resetsAt: Date(timeIntervalSince1970: 1791658800))))])
      }

      @Test func codexRolloutLine() {
          let line = #"{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":3.0,"window_minutes":300,"resets_at":1791495771},"secondary":{"used_percent":1.0,"window_minutes":10080,"resets_at":1792082571},"plan_type":"plus"}}}"#
          #expect(CodexUsage.limits(fromLine: line) == RateLimits(
              fiveHour: RateWindow(usedPercent: 3, resetsAt: Date(timeIntervalSince1970: 1791495771)),
              weekly: RateWindow(usedPercent: 1, resetsAt: Date(timeIntervalSince1970: 1792082571)),
              plan: "ChatGPT Plus"))
      }

      @Test func codexLatestSkipsSessionsWithoutLimits() throws {
          let root = FileManager.default.temporaryDirectory.appending(path: "codex-\(UUID().uuidString)")
          let day = root.appending(path: "2026/10/08")
          try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
          let with = #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":40,"window_minutes":300,"resets_at":1}}}}"#
          try (with + "\n").write(to: day.appending(path: "rollout-2026-10-08T10-00-00-a.jsonl"), atomically: true, encoding: .utf8)
          try "{\"type\":\"session_meta\"}\n".write(to: day.appending(path: "rollout-2026-10-08T11-00-00-b.jsonl"), atomically: true, encoding: .utf8)
          #expect(CodexUsage.latest(in: root)?.fiveHour?.usedPercent == 40)
      }

      @Test func claudePlanFromOrganizationType() throws {
          let file = FileManager.default.temporaryDirectory.appending(path: "claude-\(UUID().uuidString).json")
          try #"{"oauthAccount":{"organizationType":"claude_max"}}"#.write(to: file, atomically: true, encoding: .utf8)
          #expect(ClaudeAccount.plan(at: file) == "Claude Max")
      }
  }
  ```
  `UsageTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import XBotCore

  @MainActor @Suite struct UsageTests {
      let gmt = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
      let us = Locale(identifier: "en_US")

      @Test func remainingIsWhatIsLeft() {
          #expect(UsageText.remaining(RateWindow(usedPercent: 3.4, resetsAt: .now)) == "97%")
      }

      @Test func resetTodayIsATimeLaterIsADate() {
          let now = Date(timeIntervalSince1970: 1791460000)  // 2026-10-08 … UTC
          let soon = now.addingTimeInterval(3600)
          let later = now.addingTimeInterval(7 * 86400)
          #expect(UsageText.resets(soon, now: now, calendar: gmt, locale: us).hasSuffix("M"))
          #expect(UsageText.resets(later, now: now, calendar: gmt, locale: us) == "Oct 15")
      }

      @Test func updatedAgo() {
          let now = Date.now
          #expect(UsageText.updated(now.addingTimeInterval(-20), now: now) == "Updated just now")
          #expect(UsageText.updated(now.addingTimeInterval(-125), now: now) == "Updated 2 min ago")
      }

      @Test func aTurnsLimitsAreRecordedAndKept() async throws {
          let limits = RateLimits(fiveHour: RateWindow(usedPercent: 10, resetsAt: .now), weekly: nil)
          let brain = ScriptedBrain([.session("s"), .limits(limits), .textDelta("hi"), .done])
          let store = Store.inMemory()
          let w = Workspace(store: store, inbox: FileManager.default.temporaryDirectory, discover: { [.claude: brain] })
          await w.refreshHarnesses()
          let chat = try #require(w.newChat(in: nil))
          _ = w.send("hello", in: chat.id)
          for _ in 0..<200 where w.isRunning(chat.id) { await Task.yield() }
          #expect(w.usage[.claude]?.limits.fiveHour?.usedPercent == 10)
          #expect(w.messages(in: chat.id).last?.parts == [.text("hi")])
          #expect(try store.usage()[.claude]?.limits == limits)
      }
  }
  ```
- [ ] **Step 2:** `swift test --filter "RateLimitsTests|UsageTests"` → fails to compile (types missing).
- [ ] **Step 3: Implement.** `RateLimits.swift`:
  ```swift
  import Foundation

  /// One usage window: how much of it is used, and when it starts over.
  public struct RateWindow: Codable, Equatable, Sendable {
      public var usedPercent: Double
      public var resetsAt: Date
      public init(usedPercent: Double, resetsAt: Date) { self.usedPercent = usedPercent; self.resetsAt = resetsAt }
  }

  /// An agent's subscription limits as the agent itself last reported them. No credentials involved:
  /// Claude Code prints them in every turn's stream; Codex writes them into its session logs.
  public struct RateLimits: Codable, Equatable, Sendable {
      public var fiveHour: RateWindow?
      public var weekly: RateWindow?
      public var plan: String?
      public init(fiveHour: RateWindow?, weekly: RateWindow?, plan: String? = nil) {
          self.fiveHour = fiveHour; self.weekly = weekly; self.plan = plan
      }
  }

  public enum CodexUsage {
      public static var sessions: URL { URL.homeDirectory.appending(path: ".codex/sessions") }

      /// The newest session log that has limits in it. A session that just started has none yet,
      /// so a few are tried; only the last 512 KB of each is read.
      public static func latest(in root: URL = sessions) -> RateLimits? {
          for file in newestRollouts(in: root, limit: 5) {
              guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
              defer { try? handle.close() }
              let size = (try? handle.seekToEnd()) ?? 0
              try? handle.seek(toOffset: size > 524_288 ? size - 524_288 : 0)
              let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
              for line in text.split(separator: "\n").reversed() {
                  if let limits = limits(fromLine: String(line)) { return limits }
              }
          }
          return nil
      }

      static func limits(fromLine line: String) -> RateLimits? {
          guard line.contains("\"rate_limits\""), let object = jsonObject(line),
                let payload = object["payload"] as? [String: Any],
                let limits = payload["rate_limits"] as? [String: Any] else { return nil }
          func window(_ key: String) -> RateWindow? {
              guard let w = limits[key] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue,
                    let reset = (w["resets_at"] as? NSNumber)?.doubleValue else { return nil }
              return RateWindow(usedPercent: used, resetsAt: Date(timeIntervalSince1970: reset))
          }
          let result = RateLimits(fiveHour: window("primary"), weekly: window("secondary"),
                                  plan: (limits["plan_type"] as? String).flatMap(planName))
          return result.fiveHour == nil && result.weekly == nil ? nil : result
      }

      static func planName(_ type: String) -> String? {
          switch type {
          case "plus": "ChatGPT Plus"
          case "pro": "ChatGPT Pro"
          case "team": "ChatGPT Team"
          case "business": "ChatGPT Business"
          case "enterprise": "ChatGPT Enterprise"
          default: nil
          }
      }

      /// `sessions/YYYY/MM/DD/rollout-<time>-<id>.jsonl`, newest first — names sort by time.
      static func newestRollouts(in root: URL, limit: Int) -> [URL] {
          let fm = FileManager.default
          func entries(_ url: URL) -> [URL] {
              ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                  .sorted { $0.lastPathComponent > $1.lastPathComponent }
          }
          var found: [URL] = []
          for year in entries(root) { for month in entries(year) { for day in entries(month) {
              found += entries(day).filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
              if found.count >= limit { return Array(found.prefix(limit)) }
          } } }
          return found
      }
  }

  public enum ClaudeAccount {
      public static var config: URL { URL.homeDirectory.appending(path: ".claude.json") }

      /// "Claude Max", from the account summary Claude Code keeps beside its settings. Only that one
      /// field is read; the file holds no secrets, and nothing else in it is looked at.
      public static func plan(at url: URL = config) -> String? {
          guard let data = try? Data(contentsOf: url),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let account = object["oauthAccount"] as? [String: Any] else { return nil }
          switch account["organizationType"] as? String {
          case "claude_max": return "Claude Max"
          case "claude_pro": return "Claude Pro"
          case "claude_team": return "Claude Team"
          case "claude_enterprise": return "Claude Enterprise"
          default: return nil
          }
      }

      public static func isSignedIn(at url: URL = config) -> Bool {
          guard let data = try? Data(contentsOf: url),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
          return object["oauthAccount"] is [String: Any]
      }
  }
  ```
  `BrainEvent`: add `/// The agent's subscription limits, as it reported them during the turn.` `case limits(RateLimits)`.
  `ClaudeStream.events`: add
  ```swift
  case "rate_limit_event":
      guard let info = object["rate_limit_info"] as? [String: Any],
            let windows = info["unifiedWindows"] as? [String: Any] else { return [] }
      func window(_ key: String) -> RateWindow? {
          guard let w = windows[key] as? [String: Any], let used = (w["utilization"] as? NSNumber)?.doubleValue,
                let reset = (w["resetsAt"] as? NSNumber)?.doubleValue else { return nil }
          return RateWindow(usedPercent: used * 100, resetsAt: Date(timeIntervalSince1970: reset))
      }
      let limits = RateLimits(fiveHour: window("five_hour"), weekly: window("seven_day"))
      return limits.fiveHour == nil && limits.weekly == nil ? [] : [.limits(limits)]
  ```
  `Models.swift` `[Part].apply`: `case .session, .done, .structured, .limits: break`. `Workspace+Plan.drivePlanning`: `case .notice, .done, .limits: break`.
  `Usage.swift`:
  ```swift
  import Foundation

  public struct AgentUsage: Equatable, Sendable {
      public var agent: HarnessKind
      public var limits: RateLimits
      public var updatedAt: Date
  }

  /// The words and numbers of the usage menu.
  public enum UsageText {
      public static func remaining(_ window: RateWindow) -> String {
          "\(Int((100 - window.usedPercent).rounded()).clamped(to: 0...100))%"
      }

      /// "12:42 AM" when it resets today, else "Oct 15".
      public static func resets(_ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
          let formatter = DateFormatter()
          formatter.calendar = calendar
          formatter.timeZone = calendar.timeZone
          formatter.locale = locale
          formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, inSameDayAs: now) ? "jmm" : "MMMd")
          return formatter.string(from: date)
      }

      public static func updated(_ date: Date, now: Date = .now) -> String {
          let minutes = Int(now.timeIntervalSince(date) / 60)
          if minutes < 1 { return String(localized: "Updated just now") }
          if minutes < 60 { return String(localized: "Updated \(minutes) min ago") }
          return String(localized: "Updated \(minutes / 60) h ago")
      }
  }

  extension Comparable {
      func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
  }
  ```
  Store, in `migrate()`:
  ```swift
  if version < 3 {
      // Usage (2026-10-08): each agent's limits as last reported, so the menu has them after a relaunch.
      try db.execute("CREATE TABLE IF NOT EXISTS usage (agent TEXT PRIMARY KEY, limits TEXT NOT NULL, updated_at REAL NOT NULL)")
      try db.execute("PRAGMA user_version = 3")
  }
  ```
  and
  ```swift
  // MARK: Usage

  public func usage() throws -> [HarnessKind: AgentUsage] {
      var result: [HarnessKind: AgentUsage] = [:]
      for r in try db.rows("SELECT agent, limits, updated_at FROM usage") {
          guard let agent = r[0].string.flatMap(HarnessKind.init(rawValue:)), let json = r[1].string,
                let limits = try? decoder.decode(RateLimits.self, from: Data(json.utf8)) else { continue }
          result[agent] = AgentUsage(agent: agent, limits: limits, updatedAt: r[2].date)
      }
      return result
  }

  public func save(_ usage: AgentUsage) throws {
      let json = String(decoding: try encoder.encode(usage.limits), as: UTF8.self)
      try db.execute("""
          INSERT INTO usage (agent, limits, updated_at) VALUES (?, ?, ?)
          ON CONFLICT(agent) DO UPDATE SET limits = excluded.limits, updated_at = excluded.updated_at
          """, [.text(usage.agent.rawValue), .text(json), .date(usage.updatedAt)])
  }
  ```
  Workspace: new init parameters `codexUsage: @escaping @Sendable () -> RateLimits? = { CodexUsage.latest() }` and `defaults: UserDefaults = .standard` (Task 11 uses it); stored; `usage = attempt { try store.usage() } ?? [:]` in init; `public internal(set) var usage: [HarnessKind: AgentUsage] = [:]`. Every `brain.run(request)` in `Workspace.swift` and `Workspace+Plan.swift` becomes `events(brain, request, harness: chat.harness)` (the plan functions take the chat's harness from `chat(chatID)?.harness ?? .claude`).
  `Workspace+Panels.swift`:
  ```swift
  import Foundation

  extension Workspace {
      /// A brain's events, with the usage it reports taken out and kept.
      func events(_ brain: any Brain, _ request: TurnRequest, harness: HarnessKind) -> AsyncStream<BrainEvent> {
          let source = brain.run(request)
          return AsyncStream { continuation in
              let task = Task { @MainActor [weak self] in
                  for await event in source {
                      if case .limits(let limits) = event { self?.record(limits, for: harness) } else { continuation.yield(event) }
                  }
                  continuation.finish()
              }
              continuation.onTermination = { _ in task.cancel() }
          }
      }

      func record(_ limits: RateLimits, for agent: HarnessKind) {
          var limits = limits
          if limits.plan == nil { limits.plan = usage[agent]?.limits.plan }
          let entry = AgentUsage(agent: agent, limits: limits, updatedAt: .now)
          usage[agent] = entry
          attempt { try store.save(entry) }
      }

      /// Codex's limits from its newest session log. Called when the account menu opens, and each
      /// minute while it is open.
      public func refreshCodexUsage() async {
          let read = codexUsage
          guard let limits = await Task.detached(operation: { read() }).value else { return }
          if usage[.codex]?.limits != limits { record(limits, for: .codex) }
      }

      /// Claude Code's plan name, read from its account summary.
      public var claudePlan: String? { ClaudeAccount.plan() }
  }
  ```
  (`codexUsage` is an internal `let` on Workspace.)
- [ ] **Step 4:** `swift test --filter "RateLimitsTests|UsageTests"` → pass; then the whole suite → pass.
- [ ] **Step 5:** Commit `Usage: Claude Code's limits from its stream, Codex's from its logs, kept in the library.`

### Task 3: Git runner and status parser

**Files:**
- Create: `apps/mac/Sources/XBotCore/Git/GitTool.swift`, `apps/mac/Sources/XBotCore/Git/GitStatus.swift`
- Test: `apps/mac/Tests/XBotCoreTests/GitStatusTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct ProcessResult: Sendable { public var status: Int32; public var output: String; public var error: String; public var succeeded: Bool }
  public struct GitTool: Sendable {
      public let git: URL; public let gh: URL?; public let environment: [String: String]
      public static func find(searchPath: String = ..., fileExists: (String) -> Bool = ...) -> GitTool?
      public func git(_ args: [String], in dir: URL, input: String? = nil) async -> ProcessResult
      public func gh(_ args: [String], in dir: URL) async -> ProcessResult?
  }
  public struct GitFile: Equatable, Sendable, Identifiable { path, originalPath, staged: Character?, unstaged: Character?, isUntracked, isConflicted; letter: Character; isStaged }
  public struct GitStatus: Equatable, Sendable { branch, upstream, ahead, behind, files; static func parse(_:) ; state: GitState }
  public enum GitState: Equatable, Sendable { upToDate, changes(Int), toPush(Int), toPull(Int), diverged(ahead:behind:), conflict(Int), local }
  public struct DiffTotals: Equatable, Sendable { added: Int; removed: Int; static func parse(numstat:) }
  ```

- [ ] **Step 1: Failing tests**
  ```swift
  import Foundation
  import Testing
  @testable import XBotCore

  @Suite struct GitStatusTests {
      func z(_ records: String...) -> String { records.joined(separator: "\0") + "\0" }

      @Test func branchAndCounts() {
          let s = GitStatus.parse(z("# branch.oid abc", "# branch.head master", "# branch.upstream origin/master", "# branch.ab +2 -1"))
          #expect(s.branch == "master" && s.upstream == "origin/master" && s.ahead == 2 && s.behind == 1)
          #expect(s.state == .diverged(ahead: 2, behind: 1))
      }

      @Test func pathsWithSpacesAndRenames() {
          let s = GitStatus.parse(z(
              "# branch.head main",
              "1 .M N... 100644 100644 100644 aaa bbb docs/a b.md",
              "2 R. N... 100644 100644 100644 aaa bbb R100 new name.swift", "old name.swift",
              "? notes/to do.txt"))
          #expect(s.files.map(\.path) == ["docs/a b.md", "new name.swift", "notes/to do.txt"])
          #expect(s.files[0].letter == "M" && !s.files[0].isStaged)
          #expect(s.files[1].originalPath == "old name.swift" && s.files[1].letter == "R" && s.files[1].isStaged)
          #expect(s.files[2].letter == "U" && s.files[2].isUntracked)
          #expect(s.state == .changes(3))
      }

      @Test func conflictsAreConflicts() {
          let s = GitStatus.parse(z("# branch.head main", "u UU N... 100644 100644 100644 100644 a b c both.swift"))
          #expect(s.files.first?.isConflicted == true && s.files.first?.letter == "C")
          #expect(s.state == .conflict(1))
      }

      @Test func stateOrder() {
          #expect(GitStatus(branch: "m", upstream: "o/m", ahead: 0, behind: 0, files: []).state == .upToDate)
          #expect(GitStatus(branch: "m", upstream: "o/m", ahead: 3, behind: 0, files: []).state == .toPush(3))
          #expect(GitStatus(branch: "m", upstream: "o/m", ahead: 0, behind: 1, files: []).state == .toPull(1))
          #expect(GitStatus(branch: "m", upstream: nil, ahead: 0, behind: 0, files: []).state == .local)
      }

      @Test func numstatTotalsSkipBinaries() {
          #expect(DiffTotals.parse(numstat: "10\t2\ta.swift\n-\t-\tlogo.png\n3\t0\tb.md\n") == DiffTotals(added: 13, removed: 2))
      }

      @Test func gitNeverPromptsOrLocks() throws {
          let tool = try #require(GitTool.find())
          #expect(tool.environment["GIT_TERMINAL_PROMPT"] == "0")
          #expect(tool.environment["GIT_OPTIONAL_LOCKS"] == "0")
          #expect(tool.environment["GIT_SSH_COMMAND"]?.contains("BatchMode=yes") == true
                  || ProcessInfo.processInfo.environment["GIT_SSH_COMMAND"] != nil)
      }

      @Test func findSkipsTheStubWithoutCommandLineTools() {
          let tool = GitTool.find(searchPath: "/usr/bin", fileExists: { $0 == "/usr/bin/git" })
          #expect(tool == nil)
      }
  }
  ```
- [ ] **Step 2:** `swift test --filter GitStatusTests` → compile failure.
- [ ] **Step 3: Implement** `GitTool.swift`:
  ```swift
  import Foundation

  public struct ProcessResult: Sendable {
      public var status: Int32
      public var output: String
      public var error: String
      public var succeeded: Bool { status == 0 }
  }

  /// git (and GitHub's gh, when installed), run as processes in a project's folder.
  public struct GitTool: Sendable, Equatable {
      public let git: URL
      public let gh: URL?
      public let environment: [String: String]

      /// The first git on the usual PATH. `/usr/bin/git` is only a stub that offers to install the
      /// Command Line Tools, so it counts only when they (or Xcode) are there.
      /// ponytail: Xcode found at its default path only; a renamed Xcode falls back to "not installed".
      public static func find(
          searchPath: String = HarnessLocator.searchPath(loginShellPath: nil, home: NSHomeDirectory()),
          fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
      ) -> GitTool? {
          let folders = searchPath.split(separator: ":").map(String.init)
          let developerTools = fileExists("/Library/Developer/CommandLineTools/usr/bin/git")
              || fileExists("/Applications/Xcode.app/Contents/Developer/usr/bin/git")
          guard let git = folders.map({ "\($0)/git" }).first(where: { path in
              fileExists(path) && (path != "/usr/bin/git" || developerTools)
          }) else { return nil }
          let gh = folders.map { "\($0)/gh" }.first(where: fileExists)
          var env = HarnessLocator.environment(path: searchPath, base: ProcessInfo.processInfo.environment)
          // No terminal to type a password into: fail with git's message instead of waiting forever.
          env["GIT_TERMINAL_PROMPT"] = "0"
          if env["GIT_SSH_COMMAND"] == nil { env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes" }
          // `git status` must not rewrite the index: the folder watcher would see it and ask again.
          env["GIT_OPTIONAL_LOCKS"] = "0"
          return GitTool(git: URL(filePath: git), gh: gh.map { URL(filePath: $0) }, environment: env)
      }

      public func git(_ arguments: [String], in directory: URL, input: String? = nil) async -> ProcessResult {
          await run(git, arguments, in: directory, input: input)
      }

      /// Nil when gh is not installed.
      public func gh(_ arguments: [String], in directory: URL) async -> ProcessResult? {
          guard let gh else { return nil }
          return await run(gh, arguments, in: directory, input: nil)
      }

      private func run(_ executable: URL, _ arguments: [String], in directory: URL, input: String?) async -> ProcessResult {
          let process = Process()
          process.executableURL = executable
          process.arguments = arguments
          process.currentDirectoryURL = directory
          process.environment = environment
          let out = Pipe(), err = Pipe(), stdin = Pipe()
          process.standardOutput = out
          process.standardError = err
          process.standardInput = input == nil ? FileHandle.nullDevice : stdin
          do { try process.run() } catch {
              return ProcessResult(status: -1, output: "", error: error.localizedDescription)
          }
          if let input {
              let writer = stdin.fileHandleForWriting
              Task.detached { writer.write(Data(input.utf8)); try? writer.close() }
          }
          async let output = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
          async let error = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
          let (o, e) = await (output, error)
          // Both pipes are at end of file, so the process has exited or is about to.
          process.waitUntilExit()
          return ProcessResult(status: process.terminationStatus,
                               output: String(decoding: o, as: UTF8.self),
                               error: String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
      }
  }
  ```
  `GitStatus.swift`:
  ```swift
  import Foundation

  /// One changed file, from `git status --porcelain=v2`.
  public struct GitFile: Equatable, Sendable, Identifiable {
      public var path: String
      public var originalPath: String?
      /// The index's change (M, A, D, R, C), or nil.
      public var staged: Character?
      /// The working tree's change, or nil.
      public var unstaged: Character?
      public var isUntracked = false
      public var isConflicted = false
      public var id: String { path }
      public var isStaged: Bool { staged != nil }
      /// What the panel shows: C for a conflict, U untracked, else the working tree's change, else the index's.
      public var letter: Character { isConflicted ? "C" : isUntracked ? "U" : (unstaged ?? staged ?? "M") }
  }

  public enum GitState: Equatable, Sendable {
      case upToDate, changes(Int), toPush(Int), toPull(Int), diverged(ahead: Int, behind: Int), conflict(Int), local
  }

  public struct GitStatus: Equatable, Sendable {
      public var branch: String?
      public var upstream: String?
      public var ahead = 0
      public var behind = 0
      public var files: [GitFile] = []

      public init(branch: String? = nil, upstream: String? = nil, ahead: Int = 0, behind: Int = 0, files: [GitFile] = []) {
          self.branch = branch; self.upstream = upstream; self.ahead = ahead; self.behind = behind; self.files = files
      }

      /// The one state the panel leads with. Conflicts first, then what blocks a push, then work in hand.
      public var state: GitState {
          let conflicts = files.filter(\.isConflicted).count
          if conflicts > 0 { return .conflict(conflicts) }
          if ahead > 0 && behind > 0 { return .diverged(ahead: ahead, behind: behind) }
          if behind > 0 { return .toPull(behind) }
          if !files.isEmpty { return .changes(files.count) }
          if upstream == nil { return .local }
          if ahead > 0 { return .toPush(ahead) }
          return .upToDate
      }

      /// `git status --porcelain=v2 --branch -z`. Fields are space-separated up to the path, which
      /// may itself hold spaces; a rename's original path is the record after it.
      public static func parse(_ output: String) -> GitStatus {
          var status = GitStatus()
          var records = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
          func flag(_ c: Character) -> Character? { c == "." ? nil : c }
          while let record = records.popFirst() {
              if record.hasPrefix("# ") {
                  let parts = record.split(separator: " ", maxSplits: 2).map(String.init)
                  guard parts.count == 3 else { continue }
                  switch parts[1] {
                  case "branch.head": status.branch = parts[2] == "(detached)" ? nil : parts[2]
                  case "branch.upstream": status.upstream = parts[2]
                  case "branch.ab":
                      let ab = parts[2].split(separator: " ")
                      status.ahead = ab.first.flatMap { Int($0.dropFirst()) } ?? 0
                      status.behind = ab.dropFirst().first.flatMap { Int($0.dropFirst()) } ?? 0
                  default: break
                  }
                  continue
              }
              let kind = record.first
              switch kind {
              case "1", "2", "u":
                  let fields = kind == "1" ? 8 : kind == "2" ? 9 : 10
                  let parts = record.split(separator: " ", maxSplits: fields, omittingEmptySubsequences: false)
                  guard parts.count == fields + 1 else { continue }
                  let xy = Array(parts[1])
                  var file = GitFile(path: String(parts[fields]), staged: flag(xy[0]), unstaged: flag(xy[1]))
                  if kind == "2" { file.originalPath = records.popFirst() }
                  if kind == "u" { file.isConflicted = true }
                  status.files.append(file)
              case "?":
                  status.files.append(GitFile(path: String(record.dropFirst(2)), isUntracked: true))
              default:
                  break
              }
          }
          return status
      }
  }

  public struct DiffTotals: Equatable, Sendable {
      public var added = 0
      public var removed = 0
      public init(added: Int = 0, removed: Int = 0) { self.added = added; self.removed = removed }

      /// `git diff --numstat`: "added<TAB>removed<TAB>path"; binary files say "-" and are not counted.
      public static func parse(numstat: String) -> DiffTotals {
          numstat.split(separator: "\n").reduce(into: DiffTotals()) { totals, line in
              let parts = line.split(separator: "\t")
              guard parts.count >= 2 else { return }
              totals.added += Int(parts[0]) ?? 0
              totals.removed += Int(parts[1]) ?? 0
          }
      }
  }
  ```
  Note: `GitFile`'s memberwise init needs the defaulted `isUntracked`/`isConflicted`; the test's `GitFile(path:isUntracked:)` call relies on Swift's memberwise defaults — keep the property order `path, originalPath, staged, unstaged, isUntracked, isConflicted` and give `originalPath`, `staged`, `unstaged` default `nil` values (`public var originalPath: String? = nil`).
- [ ] **Step 4:** `swift test --filter GitStatusTests` → pass.
- [ ] **Step 5:** Commit `Git: find git and gh, run them without a terminal, read porcelain v2.`

### Task 4: The project git model and its actions

**Files:**
- Create: `apps/mac/Sources/XBotCore/Git/ProjectGit.swift`, `apps/mac/Sources/XBotCore/Git/PullRequest.swift`, `apps/mac/Sources/XBotCore/Git/FolderWatcher.swift`
- Modify: `apps/mac/Sources/XBotCore/Workspace+Panels.swift`
- Test: `apps/mac/Tests/XBotCoreTests/ProjectGitTests.swift`, `apps/mac/Tests/XBotCoreTests/PullRequestTests.swift`

**Interfaces:**
- Consumes: `GitTool`, `GitStatus`, `DiffTotals` (Task 3).
- Produces:
  ```swift
  @MainActor @Observable public final class ProjectGit {
      public init(directory: URL, tool: GitTool)
      public private(set) var status: GitStatus?        // nil: not loaded, or not a repository
      public private(set) var isRepository: Bool         // true until a refresh says otherwise
      public private(set) var totals: DiffTotals
      public private(set) var pullRequest: PullRequest?
      public private(set) var remote: GitHubRemote?
      public private(set) var problem: String?
      public private(set) var isBusy: Bool
      public private(set) var needsMerge: Bool           // a sync's pull could not fast-forward
      public func refresh() async
      public func fetch() async
      @discardableResult public func commit(_ message: String) async -> Bool
      public func sync() async
      public func publish() async
      public func stage(_ file: GitFile) async
      public func unstage(_ file: GitFile) async
      public func discard(_ file: GitFile) async
      public func diff(_ file: GitFile) async -> [DiffLine]      // Task 5
      public func ignored(_ paths: [String]) async -> Set<String>
      public func startWatching(); public func stopWatching()
  }
  public struct GitHubRemote: Equatable, Sendable { owner, name; webURL: URL; static func parse(_ remoteURL: String) -> GitHubRemote? }
  public struct PullRequest: Equatable, Sendable { number, state: State, review: Review?, checks: Checks?, url; static func parse(json: String) -> PullRequest? }
  Workspace.git(for project: Project) -> ProjectGit?   // nil when git is not installed
  Workspace.gitInstalled: Bool
  ```

- [ ] **Step 1: Failing tests** `PullRequestTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import XBotCore

  @Suite struct PullRequestTests {
      @Test func remotes() {
          #expect(GitHubRemote.parse("https://github.com/MasterYoav/xBot.git") == GitHubRemote(owner: "MasterYoav", name: "xBot"))
          #expect(GitHubRemote.parse("git@github.com:MasterYoav/xBot.git") == GitHubRemote(owner: "MasterYoav", name: "xBot"))
          #expect(GitHubRemote.parse("ssh://git@github.com/o/r") == GitHubRemote(owner: "o", name: "r"))
          #expect(GitHubRemote.parse("https://gitlab.com/o/r.git") == nil)
      }

      @Test func openPullRequestWithFailingCheck() {
          let json = #"{"number":15,"state":"OPEN","isDraft":false,"reviewDecision":"APPROVED","url":"https://github.com/o/r/pull/15","statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"}]}"#
          let pr = PullRequest.parse(json: json)
          #expect(pr?.number == 15 && pr?.state == .open && pr?.review == .approved && pr?.checks == .failing)
      }

      @Test func runningChecksAndStatusContexts() {
          let json = #"{"number":2,"state":"OPEN","isDraft":true,"reviewDecision":"","url":"https://x","statusCheckRollup":[{"__typename":"StatusContext","state":"PENDING"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}]}"#
          let pr = PullRequest.parse(json: json)
          #expect(pr?.state == .draft && pr?.review == nil && pr?.checks == .running)
      }
  }
  ```
  `ProjectGitTests.swift` (real git on temporary repositories with a local bare remote):
  ```swift
  import Foundation
  import Testing
  @testable import XBotCore

  /// A clone of a bare repository in a temporary folder, with one commit pushed.
  struct TempRepo {
      let root = FileManager.default.temporaryDirectory.appending(path: "xbot-git-\(UUID().uuidString)")
      var remote: URL { root.appending(path: "remote.git") }
      var work: URL { root.appending(path: "work") }

      func sh(_ args: String..., in dir: URL? = nil) throws {
          let p = Process()
          p.executableURL = URL(filePath: "/usr/bin/env")
          p.arguments = ["git"] + args
          p.currentDirectoryURL = dir ?? work
          p.standardOutput = FileHandle.nullDevice
          p.standardError = FileHandle.nullDevice
          try p.run(); p.waitUntilExit()
          guard p.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
      }

      func write(_ name: String, _ text: String, in dir: URL? = nil) throws {
          try text.write(to: (dir ?? work).appending(path: name), atomically: true, encoding: .utf8)
      }

      static func make() throws -> TempRepo {
          let repo = TempRepo()
          try FileManager.default.createDirectory(at: repo.root, withIntermediateDirectories: true)
          try repo.sh("init", "--bare", "-b", "main", repo.remote.path, in: repo.root)
          try repo.sh("clone", repo.remote.path, repo.work.path, in: repo.root)
          for (k, v) in [("user.name", "Test"), ("user.email", "t@example.com"), ("commit.gpgsign", "false")] { try repo.sh("config", k, v) }
          try repo.write("a.txt", "one\n")
          try repo.sh("add", ".")
          try repo.sh("commit", "-m", "first")
          try repo.sh("push", "-u", "origin", "HEAD")
          return repo
      }

      /// A second clone that pushes a commit, so the first is behind.
      func pushFromElsewhere(_ name: String) throws {
          let other = root.appending(path: "other-\(UUID().uuidString)")
          try sh("clone", remote.path, other.path, in: root)
          for (k, v) in [("user.name", "Other"), ("user.email", "o@example.com"), ("commit.gpgsign", "false")] { try sh("config", k, v, in: other) }
          try write(name, "theirs\n", in: other)
          try sh("add", ".", in: other)
          try sh("commit", "-m", "theirs", in: other)
          try sh("push", in: other)
      }
  }

  @MainActor @Suite struct ProjectGitTests {
      let tool = GitTool.find()!

      @Test func cleanIsUpToDate() async throws {
          let repo = try TempRepo.make()
          let git = ProjectGit(directory: repo.work, tool: tool)
          await git.refresh()
          #expect(git.status?.state == .upToDate && git.status?.branch == "main")
      }

      @Test func notARepository() async throws {
          let folder = FileManager.default.temporaryDirectory.appending(path: "plain-\(UUID().uuidString)")
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let git = ProjectGit(directory: folder, tool: tool)
          await git.refresh()
          #expect(!git.isRepository && git.status == nil)
      }

      @Test func commitStagesEverythingWhenNothingIsStaged() async throws {
          let repo = try TempRepo.make()
          try repo.write("a.txt", "one\ntwo\n")
          try repo.write("b.txt", "new\n")
          let git = ProjectGit(directory: repo.work, tool: tool)
          await git.refresh()
          #expect(git.status?.state == .changes(2))
          #expect(git.totals == DiffTotals(added: 1, removed: 0))
          #expect(await git.commit("Two files"))
          #expect(git.status?.state == .toPush(1))
          await git.sync()
          #expect(git.status?.state == .upToDate)
      }

      @Test func commitOnlyWhatIsStaged() async throws {
          let repo = try TempRepo.make()
          try repo.write("a.txt", "changed\n")
          try repo.write("b.txt", "new\n")
          let git = ProjectGit(directory: repo.work, tool: tool)
          await git.refresh()
          let b = try #require(git.status?.files.first { $0.path == "b.txt" })
          await git.stage(b)
          #expect(git.status?.files.first { $0.path == "b.txt" }?.isStaged == true)
          #expect(await git.commit("Just b"))
          #expect(git.status?.files.map(\.path) == ["a.txt"])
      }

      @Test func discardRestoresATrackedFileAndRemovesAnUntrackedOne() async throws {
          let repo = try TempRepo.make()
          try repo.write("a.txt", "changed\n")
          try repo.write("c.txt", "scratch\n")
          let git = ProjectGit(directory: repo.work, tool: tool)
          await git.refresh()
          for file in git.status?.files ?? [] { await git.discard(file) }
          #expect(git.status?.state == .upToDate)
          #expect(try String(contentsOf: repo.work.appending(path: "a.txt"), encoding: .utf8) == "one\n")
      }

      @Test func syncPullsThenPushes() async throws {
          let repo = try TempRepo.make()
          try repo.pushFromElsewhere("theirs.txt")
          let git = ProjectGit(directory: repo.work, tool: tool)
          await git.fetch()
          #expect(git.status?.state == .toPull(1))
          await git.sync()
          #expect(git.status?.state == .upToDate)
          #expect(FileManager.default.fileExists(atPath: repo.work.appending(path: "theirs.txt").path))
      }

      @Test func divergedSyncAsksForAMerge() async throws {
          let repo = try TempRepo.make()
          try repo.pushFromElsewhere("theirs.txt")
          try repo.write("mine.txt", "mine\n")
          let git = ProjectGit(directory: repo.work, tool: tool)
          await git.refresh()
          _ = await git.commit("Mine")
          await git.fetch()
          #expect(git.status?.state == .diverged(ahead: 1, behind: 1))
          await git.sync()
          #expect(git.needsMerge)
          #expect(git.status?.state == .diverged(ahead: 1, behind: 1))
      }

      @Test func publishSetsTheUpstream() async throws {
          let repo = try TempRepo.make()
          try repo.sh("switch", "-c", "feature")
          let git = ProjectGit(directory: repo.work, tool: tool)
          await git.refresh()
          #expect(git.status?.state == .local)
          await git.publish()
          #expect(git.status?.upstream == "origin/feature")
      }

      @Test func ignoredPaths() async throws {
          let repo = try TempRepo.make()
          try repo.write(".gitignore", "build/\n*.log\n")
          let git = ProjectGit(directory: repo.work, tool: tool)
          #expect(await git.ignored(["build", "a.txt", "x.log"]) == ["build", "x.log"])
      }

      @Test func aFailedCommandIsShownNotThrown() async throws {
          let repo = try TempRepo.make()
          let git = ProjectGit(directory: repo.work, tool: tool)
          await git.refresh()
          #expect(await git.commit("nothing to commit") == false)
          #expect(git.problem != nil)
      }
  }
  ```
- [ ] **Step 2:** `swift test --filter "ProjectGitTests|PullRequestTests"` → compile failure.
- [ ] **Step 3: Implement** `PullRequest.swift`:
  ```swift
  import Foundation

  /// A GitHub repository, from a remote's URL (https, scp-style ssh, or ssh://).
  public struct GitHubRemote: Equatable, Sendable {
      public var owner: String
      public var name: String
      public var webURL: URL { URL(string: "https://github.com/\(owner)/\(name)")! }
      public var slug: String { "\(owner)/\(name)" }

      public static func parse(_ remote: String) -> GitHubRemote? {
          let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
          let path: Substring
          if let range = trimmed.range(of: "github.com:") ?? trimmed.range(of: "github.com/") {
              path = trimmed[range.upperBound...]
          } else { return nil }
          let parts = path.split(separator: "/")
          guard parts.count >= 2 else { return nil }
          let name = parts[1].hasSuffix(".git") ? parts[1].dropLast(4) : parts[1]
          return GitHubRemote(owner: String(parts[0]), name: String(name))
      }
  }

  /// The branch's pull request, as `gh pr view --json` reports it.
  public struct PullRequest: Equatable, Sendable {
      public enum State: Sendable { case open, draft, merged, closed }
      public enum Review: Sendable { case required, approved, changesRequested }
      public enum Checks: Sendable { case passing, failing, running }

      public var number: Int
      public var state: State
      public var review: Review?
      public var checks: Checks?
      public var url: URL?

      public static let fields = "number,state,isDraft,reviewDecision,url,statusCheckRollup"

      public static func parse(json: String) -> PullRequest? {
          guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
                let number = object["number"] as? Int else { return nil }
          let state: State = switch object["state"] as? String {
          case "MERGED": .merged
          case "CLOSED": .closed
          default: object["isDraft"] as? Bool == true ? .draft : .open
          }
          let review: Review? = switch object["reviewDecision"] as? String {
          case "APPROVED": .approved
          case "CHANGES_REQUESTED": .changesRequested
          case "REVIEW_REQUIRED": .required
          default: nil
          }
          let rollup = object["statusCheckRollup"] as? [[String: Any]] ?? []
          let outcomes: [Checks] = rollup.map { check in
              if let state = check["state"] as? String {   // a StatusContext
                  return switch state { case "SUCCESS": .passing; case "PENDING", "EXPECTED": .running; default: .failing }
              }
              guard check["status"] as? String == "COMPLETED" else { return .running }
              return switch check["conclusion"] as? String {
              case "SUCCESS", "NEUTRAL", "SKIPPED": .passing
              default: .failing
              }
          }
          let checks: Checks? = outcomes.isEmpty ? nil
              : outcomes.contains(.failing) ? .failing : outcomes.contains(.running) ? .running : .passing
          return PullRequest(number: number, state: state, review: review, checks: checks,
                             url: (object["url"] as? String).flatMap(URL.init(string:)))
      }
  }
  ```
  `FolderWatcher.swift`:
  ```swift
  import CoreServices
  import Foundation

  /// Calls back on the main queue when anything under a folder changes, at most every 300 ms
  /// (FSEvents' own latency does the debouncing).
  public final class FolderWatcher {
      private var stream: FSEventStreamRef?
      private let callback: Box

      private final class Box { let action: @MainActor () -> Void; init(_ a: @escaping @MainActor () -> Void) { action = a } }

      public init(_ folder: URL, latency: TimeInterval = 0.3, onChange: @escaping @MainActor () -> Void) {
          callback = Box(onChange)
          var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(callback).toOpaque(),
                                             retain: nil, release: nil, copyDescription: nil)
          stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
              guard let info else { return }
              let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
              MainActor.assumeIsolated { box.action() }
          }, &context, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
             FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
          if let stream {
              FSEventStreamSetDispatchQueue(stream, .main)
              FSEventStreamStart(stream)
          }
      }

      deinit {
          if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
      }
  }
  ```
  `ProjectGit.swift`:
  ```swift
  import Foundation
  import Observation

  /// One project's git: what state it is in, and the everyday actions on it. Every action ends by
  /// reading the status again; a failing command leaves its message in `problem`.
  @MainActor
  @Observable
  public final class ProjectGit {
      public let directory: URL
      let tool: GitTool
      public private(set) var status: GitStatus?
      public private(set) var isRepository = true
      public private(set) var totals = DiffTotals()
      public private(set) var pullRequest: PullRequest?
      public private(set) var remote: GitHubRemote?
      public private(set) var problem: String?
      public private(set) var isBusy = false
      public private(set) var needsMerge = false
      /// Bumped on every refresh, so the explorer knows to read its folders and colours again.
      public private(set) var generation = 0
      @ObservationIgnored private var watcher: FolderWatcher?

      public init(directory: URL, tool: GitTool) {
          self.directory = directory
          self.tool = tool
      }

      public func refresh() async {
          guard await tool.git(["rev-parse", "--is-inside-work-tree"], in: directory).succeeded else {
              isRepository = false; status = nil; totals = DiffTotals(); generation += 1
              return
          }
          isRepository = true
          let result = await tool.git(["status", "--porcelain=v2", "--branch", "-z"], in: directory)
          guard result.succeeded else { problem = result.error; return }
          status = GitStatus.parse(result.output)
          if status?.behind == 0 { needsMerge = false }
          // A repository with no commit yet has no HEAD to compare with: no totals, not an error.
          let numstat = await tool.git(["diff", "--numstat", "HEAD"], in: directory)
          totals = numstat.succeeded ? DiffTotals.parse(numstat: numstat.output) : DiffTotals()
          generation += 1
          await refreshPullRequest()
      }

      private func refreshPullRequest() async {
          let url = await tool.git(["remote", "get-url", "origin"], in: directory)
          remote = url.succeeded ? GitHubRemote.parse(url.output) : nil
          guard let remote, let branch = status?.branch,
                let result = await tool.gh(["pr", "view", branch, "-R", remote.slug, "--json", PullRequest.fields], in: directory),
                result.succeeded else { pullRequest = nil; return }
          pullRequest = PullRequest.parse(json: result.output)
      }

      public func fetch() async { await perform(["fetch", "--quiet"]) }

      /// Commits what is staged, or everything when nothing is.
      @discardableResult
      public func commit(_ message: String) async -> Bool {
          let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !message.isEmpty else { return false }
          if !(status?.files.contains(where: \.isStaged) ?? false) {
              guard await perform(["add", "-A"], refreshing: false) else { return false }
          }
          return await perform(["commit", "-m", message])
      }

      /// Pull (fast-forward only), then push. A pull that cannot fast-forward stops there and
      /// `needsMerge` is set: merging is the agent's job, not a button's.
      public func sync() async {
          if (status?.behind ?? 0) > 0 {
              let pulled = await run(["pull", "--ff-only"])
              guard pulled.succeeded else {
                  needsMerge = true
                  await refresh()
                  return
              }
          }
          if status?.upstream == nil { await publish(); return }
          await perform(["push"])
      }

      /// Pushes a branch that has no upstream yet, and sets it.
      public func publish() async {
          guard let branch = status?.branch else { return }
          let remotes = await tool.git(["remote"], in: directory).output.split(separator: "\n").map(String.init)
          guard let remote = remotes.contains("origin") ? "origin" : remotes.first else {
              problem = String(localized: "This repository has no remote to publish to.")
              return
          }
          await perform(["push", "-u", remote, branch])
      }

      public func stage(_ file: GitFile) async {
          await perform(["add", "--"] + [file.path] + (file.originalPath.map { [$0] } ?? []))
      }

      public func unstage(_ file: GitFile) async {
          await perform(["restore", "--staged", "--"] + [file.path] + (file.originalPath.map { [$0] } ?? []))
      }

      /// Throws away the file's changes. An untracked file goes to the Trash; a tracked one is
      /// restored from the last commit.
      public func discard(_ file: GitFile) async {
          let url = directory.appending(path: file.path)
          if file.isUntracked {
              do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { problem = error.localizedDescription }
              await refresh()
          } else if file.staged == "A" {
              guard await perform(["rm", "--cached", "--quiet", "--", file.path], refreshing: false) else { return }
              try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
              await refresh()
          } else {
              await perform(["restore", "--source=HEAD", "--staged", "--worktree", "--"] + [file.path] + (file.originalPath.map { [$0] } ?? []))
          }
      }

      /// Of these project-relative paths, the ones git ignores.
      public func ignored(_ paths: [String]) async -> Set<String> {
          guard !paths.isEmpty else { return [] }
          let result = await tool.git(["check-ignore", "--stdin", "-z"], in: directory, input: paths.joined(separator: "\0") + "\0")
          return Set(result.output.split(separator: "\0").map(String.init))
      }

      public func startWatching() {
          guard watcher == nil else { return }
          watcher = FolderWatcher(directory) { [weak self] in Task { await self?.refresh() } }
      }

      public func stopWatching() { watcher = nil }

      public func clearProblem() { problem = nil }

      // MARK: Running

      private func run(_ arguments: [String]) async -> ProcessResult {
          await tool.git(arguments, in: directory)
      }

      /// Runs a command; on failure keeps git's message. Refreshes afterwards unless asked not to.
      @discardableResult
      private func perform(_ arguments: [String], refreshing: Bool = true) async -> Bool {
          isBusy = true
          defer { isBusy = false }
          let result = await run(arguments)
          problem = result.succeeded ? nil : (result.error.isEmpty ? result.output : result.error)
          if refreshing { await refresh() }
          return result.succeeded
      }
  }
  ```
  `Workspace+Panels.swift` additions:
  ```swift
  /// git, if this Mac has it.
  public var gitInstalled: Bool { gitTool != nil }

  /// The project's git model, made once and kept. Nil when git is not installed.
  public func git(for project: Project) -> ProjectGit? {
      guard let tool = gitTool else { return nil }
      if let model = gitModels[project.id] { return model }
      let model = ProjectGit(directory: project.url, tool: tool)
      gitModels[project.id] = model
      return model
  }
  ```
  with, on Workspace, `@ObservationIgnored var gitModels: [UUID: ProjectGit] = [:]` and `@ObservationIgnored lazy var gitTool: GitTool? = GitTool.find()` (or found in init — `lazy` is not allowed with `@Observable`; use `let gitTool: GitTool?` initialised from a new init parameter `gitTool: GitTool? = GitTool.find()`).
- [ ] **Step 4:** `swift test --filter "ProjectGitTests|PullRequestTests"` → pass. Run `ProjectGitTests` five times (`for i in 1 2 3 4 5; do swift test --filter ProjectGitTests || break; done`) — they spawn processes in parallel.
- [ ] **Step 5:** Commit `Git: the project's state, commit, sync, publish, stage, discard, and its pull request.`

### Task 5: Diff lines

**Files:**
- Create: `apps/mac/Sources/XBotCore/Git/UnifiedDiff.swift`
- Modify: `ProjectGit.swift` (`diff(_:)`)
- Test: `apps/mac/Tests/XBotCoreTests/UnifiedDiffTests.swift`

**Interfaces:**
- Produces: `public struct DiffLine: Equatable, Sendable, Identifiable { enum Kind { hunk, context, added, removed }; id: Int; kind; old: Int?; new: Int?; text: String }`, `UnifiedDiff.parse(_:) -> [DiffLine]`, `ProjectGit.diff(_ file: GitFile) async -> [DiffLine]`.

- [ ] **Step 1: Failing tests**
  ```swift
  import Foundation
  import Testing
  @testable import XBotCore

  @MainActor @Suite struct UnifiedDiffTests {
      @Test func numbersFollowTheHunk() {
          let text = """
          diff --git a/a.txt b/a.txt
          --- a/a.txt
          +++ b/a.txt
          @@ -3,3 +3,3 @@ func x()
           keep
          -old
          +new
          \\ No newline at end of file
          """
          let lines = UnifiedDiff.parse(text)
          #expect(lines.map(\.kind) == [.hunk, .context, .removed, .added])
          #expect(lines[1].old == 3 && lines[1].new == 3)
          #expect(lines[2].old == 4 && lines[2].new == nil)
          #expect(lines[3].old == nil && lines[3].new == 4)
          #expect(lines[3].text == "new")
      }

      @Test func anUntrackedFileDiffsAsAllAdded() async throws {
          let repo = try TempRepo.make()
          try repo.write("fresh.txt", "a\nb\n")
          let git = ProjectGit(directory: repo.work, tool: GitTool.find()!)
          await git.refresh()
          let file = try #require(git.status?.files.first { $0.path == "fresh.txt" })
          let lines = await git.diff(file)
          #expect(lines.filter { $0.kind == .added }.map(\.text) == ["a", "b"])
          #expect(git.problem == nil)
      }

      @Test func aTrackedFileDiffsAgainstTheLastCommit() async throws {
          let repo = try TempRepo.make()
          try repo.write("a.txt", "two\n")
          let git = ProjectGit(directory: repo.work, tool: GitTool.find()!)
          await git.refresh()
          let lines = await git.diff(try #require(git.status?.files.first))
          #expect(lines.filter { $0.kind != .hunk }.map(\.text) == ["one", "two"])
      }
  }
  ```
- [ ] **Step 2:** `swift test --filter UnifiedDiffTests` → compile failure.
- [ ] **Step 3: Implement**
  ```swift
  import Foundation

  public struct DiffLine: Equatable, Sendable, Identifiable {
      public enum Kind: Sendable { case hunk, context, added, removed }
      public var id: Int
      public var kind: Kind
      public var old: Int?
      public var new: Int?
      public var text: String
  }

  /// A unified diff as numbered lines. Headers before the first hunk are dropped.
  public enum UnifiedDiff {
      public static func parse(_ text: String) -> [DiffLine] {
          var lines: [DiffLine] = []
          var old = 0, new = 0, inHunk = false
          for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
              let line = String(raw)
              if line.hasPrefix("@@") {
                  inHunk = true
                  let numbers = line.split(separator: " ")
                  old = numbers.count > 1 ? Int(numbers[1].dropFirst().split(separator: ",")[0]) ?? 0 : 0
                  new = numbers.count > 2 ? Int(numbers[2].dropFirst().split(separator: ",")[0]) ?? 0 : 0
                  lines.append(DiffLine(id: lines.count, kind: .hunk, text: line))
                  continue
              }
              guard inHunk, let first = line.first else { continue }
              switch first {
              case " ": lines.append(DiffLine(id: lines.count, kind: .context, old: old, new: new, text: String(line.dropFirst()))); old += 1; new += 1
              case "-": lines.append(DiffLine(id: lines.count, kind: .removed, old: old, text: String(line.dropFirst()))); old += 1
              case "+": lines.append(DiffLine(id: lines.count, kind: .added, new: new, text: String(line.dropFirst()))); new += 1
              default: break   // "\ No newline at end of file"
              }
          }
          return lines
      }
  }
  ```
  (Give `DiffLine` an explicit `init(id:kind:old: Int? = nil, new: Int? = nil, text:)`.)
  `ProjectGit`:
  ```swift
  /// The file's changes against the last commit. An untracked file is compared with nothing —
  /// `--no-index` exits 1 when files differ, which here is the normal answer.
  public func diff(_ file: GitFile) async -> [DiffLine] {
      let result = file.isUntracked
          ? await tool.git(["diff", "--no-index", "--no-color", "--", "/dev/null", file.path], in: directory)
          : await tool.git(["diff", "--no-color", "HEAD", "--", file.path], in: directory)
      guard result.status == 0 || (file.isUntracked && result.status == 1) else {
          problem = result.error
          return []
      }
      return UnifiedDiff.parse(result.output)
  }
  ```
- [ ] **Step 4:** `swift test --filter UnifiedDiffTests` → pass.
- [ ] **Step 5:** Commit `Git: a file's diff as numbered lines, untracked files included.`

### Task 6: Changes panel, diff view and the inspector

**Files:**
- Create: `apps/mac/Sources/XBotUI/Inspector/InspectorView.swift`, `ChangesPanel.swift`, `DiffView.swift`
- Modify: `RootView.swift` (diff page), `Workspace+Panels.swift` (page state, ask-to-merge)
- Test: `apps/mac/Tests/XBotCoreTests/PanelsTests.swift`

**Interfaces:**
- Consumes: `ProjectGit` (Task 4), `DiffLine` (Task 5), `contextProject` (Task 1).
- Produces:
  ```swift
  public enum Page: Equatable, Sendable { case main, profile, diff(projectID: UUID, file: GitFile) }
  Workspace.page: Page          // reset to .main by open(_:) and goHome()
  Workspace.showDiff(_ file: GitFile, in project: Project)
  Workspace.askToMerge()        // sends the merge request to the open chat, or puts it in Home's draft
  ```

- [ ] **Step 1: Failing tests** `PanelsTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import XBotCore

  @MainActor @Suite struct PanelsTests {
      func workspace(_ brain: ScriptedBrain = ScriptedBrain([.done])) async -> Workspace {
          let w = Workspace(store: .inMemory(), inbox: FileManager.default.temporaryDirectory,
                            discover: { [.claude: brain] }, defaults: UserDefaults(suiteName: UUID().uuidString)!)
          await w.refreshHarnesses()
          return w
      }

      @Test func openingAChatLeavesTheProfile() async throws {
          let w = await workspace()
          w.page = .profile
          let chat = try #require(w.newChat(in: nil))
          #expect(w.page == .main)
          w.page = .profile
          w.goHome()
          #expect(w.page == .main)
          _ = chat
      }

      @Test func askToMergeSendsToTheOpenChat() async throws {
          let brain = ScriptedBrain([.done])
          let w = await workspace(brain)
          let chat = try #require(w.newChat(in: nil))
          w.askToMerge()
          for _ in 0..<200 where w.isRunning(chat.id) { await Task.yield() }
          #expect(brain.requests.withLock { $0.first?.prompt.contains("merge") } == true)
      }

      @Test func askToMergeOnHomeFillsTheDraft() async {
          let w = await workspace()
          w.askToMerge()
          #expect(w.draft.text.contains("merge"))
      }
  }
  ```
- [ ] **Step 2:** `swift test --filter PanelsTests` → compile failure (`page`, `askToMerge`, `defaults:`).
- [ ] **Step 3: Implement core.** In `Workspace.swift`: `public var page: Page = .main`; `open(_:)` sets `page = .main`. In `Workspace+Home.swift` `goHome()` sets `page = .main`. `Workspace+Panels.swift`:
  ```swift
  public enum Page: Equatable, Sendable {
      case main, profile
      case diff(projectID: UUID, file: GitFile)
  }

  extension Workspace {
      public func showDiff(_ file: GitFile, in project: Project) { page = .diff(projectID: project.id, file: file) }

      public static var mergeRequest: String {
          String(localized: "Pull the latest changes from the remote and merge them with mine. Resolve any conflicts, run the tests, then tell me what you did.")
      }

      /// "Ask the agent to merge": to the open chat, or into Home's composer.
      public func askToMerge() {
          if let id = selectedChatID, send(Self.mergeRequest, in: id) { return }
          draft.text = Self.mergeRequest
          composerFocusRequest += 1
      }
  }
  ```
- [ ] **Step 4: Views.**
  `InspectorView`: header row (height `Metrics.titleBar`, `.background(Palette.sidebar)`): two segment buttons — "Explorer" and the totals `Text("+\(totals.added)").foregroundStyle(Palette.success)` / `Text("−\(totals.removed)").foregroundStyle(Palette.failure)` in `Typography.mono` — selected one on `Palette.hover` capsule; `@AppStorage("inspectorTab") private var tab = "changes"`. Body: `ChangesPanel` or `ExplorerPanel` (Task 7; a placeholder `Text` until then). `.task(id: project.id) { await git.refresh(); git.startWatching(); while !Task.isCancelled { try? await Task.sleep(for: .seconds(300)); await git.fetch() } }` and `.onDisappear { git.stopWatching() }`. When `workspace.git(for:)` is nil: `ContentUnavailableView(String(localized: "Git isn't installed on this Mac."), systemImage: "arrow.triangle.branch")` with a `Button(String(localized: "Install Command Line Tools"))` running `Process` `/usr/bin/xcode-select --install`.
  `ChangesPanel` (ScrollView, `Space.m` padding, `VStack(alignment: .leading, spacing: Space.m)`):
  1. Header: `Text("Changes").emphasisText()`; then `Label(branch, systemImage: "arrow.triangle.branch").captionText()` with `↓\(behind)` / `↑\(ahead)` mono when non-zero; trailing `Menu { Button("Fetch Now") { Task { await git.fetch() } }; if let remote = git.remote { Button("Open on GitHub") { NSWorkspace.shared.open(remote.webURL) } } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()`.
  2. State line: `StatusPill(pill.state, pill.text)` + sentence, from a private `func describe(_ state: GitState, upstream: String?) -> (PillState, String, String)` implementing the spec table verbatim; not a repo → `(.neutral, "NO GIT", "This folder isn't a git repository.")`. `.local` shows a `Button("Publish") { Task { await git.publish() } }.buttonStyle(PrimaryButtonStyle())`.
  3. PR row when `git.pullRequest != nil`: `Link` to the URL: "PR #15 · open" + review words ("review requested" / "approved" / "changes requested") + checks pill (`.success "PASSING"`, `.failure "FAILING"`, `.running "RUNNING"`).
  4. Problem: `if let problem = git.problem { Text(problem).font(Typography.mono).foregroundStyle(Palette.failure).padding(Space.s).background(Palette.failureTint, in: RoundedRectangle(cornerRadius: Radius.small)) }` with an ✕ calling `git.clearProblem()`.
  5. Commit: `TextField(String(localized: "Message (⌘↩ to commit)"), text: $message, axis: .vertical)` on `InsetPanel`; buttons `Commit` (Primary, disabled when the message is empty or there are no files; `.keyboardShortcut(.return, modifiers: .command)`) and `Sync Changes ↓\(behind) ↑\(ahead)` (Quiet; disabled when both are 0 and upstream exists). On success clear `message`.
  6. Needs merge: when `git.needsMerge || state is .diverged`, a callout "Pull before you push…" with `Button("Ask the agent to merge") { workspace.askToMerge() }`.
  7. Files: `ForEach(status.files)` rows: `Image(systemName: FileIcon.symbol(for: name, isFolder: false))`, name (`Typography.body`), directory (`captionText`, tertiary), trailing letter (`Typography.mono`, colour: M/R amber `Palette.warning`, A/U `Palette.success`, D/C `Palette.failure`). On hover: `IconButton(file.isStaged ? "minus" : "plus", …)` and `IconButton("arrow.uturn.backward", help: "Discard Changes")` → sets `discarding = file`, `.confirmationDialog(String(localized: "Discard changes to \(file.path)?"), isPresented:…) { Button("Discard", role: .destructive) { Task { await git.discard(file) } } } message: { Text("This can't be undone.") }`. Tap → `workspace.showDiff(file, in: project)`.
  `DiffView(workspace:, project:, file:)`: header row (file path mono, ✕ `IconButton("xmark")` → `workspace.page = .main`, `.onExitCommand` the same); `ScrollView([.vertical, .horizontal])` `LazyVStack(alignment: .leading, spacing: 0)` rows: old and new numbers right-aligned in `Typography.mono` tertiary, width 40 each; the text mono; `.background` `Palette.successTint` for added, `Palette.failureTint` for removed, `Palette.inset` for hunks. Loads with `.task(id: file) { lines = await git.diff(file) }`.
  RootView page switch inside the content `ZStack`: `switch workspace.page { case .profile: ProfileView(workspace:) (Task 10; placeholder until then); case .diff(let projectID, let file): if let project = workspace.projects.first(where: { $0.id == projectID }), let git = workspace.git(for: project) { DiffView(...) }; case .main: chat or Home }`.
- [ ] **Step 5:** `swift build --build-tests && swift test` → pass. Run the app on this repository's worktree; check each state by eye (clean, edit a file, commit, the PR row), and the diff view.
- [ ] **Step 6:** Commit `Inspector: the Changes panel — state, pull request, commit, sync, files and their diffs.`

### Task 7: Explorer

**Files:**
- Create: `apps/mac/Sources/XBotCore/FileTree.swift`, `apps/mac/Sources/XBotUI/Inspector/ExplorerPanel.swift`, `apps/mac/Sources/XBotUI/Inspector/FileIcon.swift`
- Modify: `Workspace+Panels.swift` (mention), `Chat/Composer.swift` (mention requests; file drops)
- Test: `apps/mac/Tests/XBotCoreTests/FileTreeTests.swift`

**Interfaces:**
- Consumes: `GitStatus` (Task 3), `ProjectGit.ignored`, `ProjectGit.generation` (Task 4).
- Produces:
  ```swift
  public struct FileNode: Identifiable, Equatable, Sendable { url: URL; name: String; isFolder: Bool; isDeleted: Bool; id: String { url.path } }
  public enum FileTree {
      static func children(of folder: URL, root: URL, deleted: [String]) -> [FileNode]
      static func letters(_ status: GitStatus) -> [String: Character]   // file and every parent folder
      static func relativePath(_ url: URL, in root: URL) -> String
      static func mention(_ url: URL, in root: URL) -> String           // "@docs/a.md"
      static func newName(_ base: String, in folder: URL) -> String      // "untitled", "untitled 2", …
  }
  Workspace.mention(_ url: URL)                 // queues "@path " for the visible composer
  Workspace.pendingMention: String?; Workspace.mentionRequest: Int
  ```

- [ ] **Step 1: Failing tests**
  ```swift
  import Foundation
  import Testing
  @testable import XBotCore

  @MainActor @Suite struct FileTreeTests {
      func folder() throws -> URL {
          let root = FileManager.default.temporaryDirectory.appending(path: "tree-\(UUID().uuidString)")
          for dir in ["src", "Docs"] { try FileManager.default.createDirectory(at: root.appending(path: dir), withIntermediateDirectories: true) }
          for file in ["b.swift", "a.md", ".DS_Store", "src/x.swift"] { try "".write(to: root.appending(path: file), atomically: true, encoding: .utf8) }
          return root
      }

      @Test func foldersFirstThenFilesByName() throws {
          let root = try folder()
          #expect(FileTree.children(of: root, root: root, deleted: []).map(\.name) == ["Docs", "src", "a.md", "b.swift"])
      }

      @Test func deletedFilesAppearWhereTheyWere() throws {
          let root = try folder()
          let names = FileTree.children(of: root.appending(path: "src"), root: root, deleted: ["src/gone.swift", "other/no.swift"])
          #expect(names.map(\.name) == ["gone.swift", "x.swift"])
          #expect(names.first?.isDeleted == true)
      }

      @Test func aFolderTakesTheStrongestLetterInside() {
          let status = GitStatus(files: [
              GitFile(path: "src/a.swift", unstaged: "M"),
              GitFile(path: "src/deep/b.swift", isUntracked: true),
              GitFile(path: "docs/c.md", unstaged: "D"),
          ])
          let letters = FileTree.letters(status)
          #expect(letters["src"] == "M" && letters["src/deep"] == "U" && letters["docs"] == "D" && letters["src/a.swift"] == "M")
      }

      @Test func mentionIsRelative() throws {
          let root = try folder()
          #expect(FileTree.mention(root.appending(path: "src/x.swift"), in: root) == "@src/x.swift")
      }

      @Test func newNamesDoNotCollide() throws {
          let root = try folder()
          try "".write(to: root.appending(path: "untitled"), atomically: true, encoding: .utf8)
          #expect(FileTree.newName("untitled", in: root) == "untitled 2")
      }

      @Test func mentionReachesTheComposer() async throws {
          let w = Workspace(store: .inMemory(), inbox: FileManager.default.temporaryDirectory, discover: { [:] },
                            defaults: UserDefaults(suiteName: UUID().uuidString)!)
          let root = try folder()
          let project = w.addProject(at: root)
          w.startDraft(in: project.id)
          let before = w.mentionRequest
          w.mention(root.appending(path: "a.md"))
          #expect(w.pendingMention == "@a.md" && w.mentionRequest == before + 1)
      }
  }
  ```
- [ ] **Step 2:** `swift test --filter FileTreeTests` → compile failure.
- [ ] **Step 3: Implement** `FileTree.swift`:
  ```swift
  import Foundation

  public struct FileNode: Identifiable, Equatable, Sendable {
      public var url: URL
      public var name: String
      public var isFolder: Bool
      public var isDeleted = false
      public var id: String { url.path }
  }

  /// The explorer's view of a folder: what is in it, and how git sees each thing.
  public enum FileTree {
      static let hidden: Set<String> = [".DS_Store"]

      /// Folders first, then files, each by name as Finder sorts. Files git knows were deleted are
      /// listed where they were, so the tree shows them struck through.
      public static func children(of folder: URL, root: URL, deleted: [String]) -> [FileNode] {
          let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
          var nodes = urls.filter { !hidden.contains($0.lastPathComponent) }.map { url in
              FileNode(url: url, name: url.lastPathComponent,
                       isFolder: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
          }
          let here = relativePath(folder, in: root)
          for path in deleted where (path as NSString).deletingLastPathComponent == here {
              let url = root.appending(path: path)
              if !nodes.contains(where: { $0.url.lastPathComponent == url.lastPathComponent }) {
                  nodes.append(FileNode(url: url, name: url.lastPathComponent, isFolder: false, isDeleted: true))
              }
          }
          return nodes.sorted { a, b in
              a.isFolder != b.isFolder ? a.isFolder : a.name.localizedStandardCompare(b.name) == .orderedAscending
          }
      }

      /// Each changed file's letter, and each folder above it the strongest letter inside:
      /// conflict, then deleted, then modified, then added.
      public static func letters(_ status: GitStatus) -> [String: Character] {
          func rank(_ c: Character) -> Int { switch c { case "C": 4; case "D": 3; case "M", "R": 2; default: 1 } }
          var result: [String: Character] = [:]
          for file in status.files {
              result[file.path] = file.letter
              var folder = (file.path as NSString).deletingLastPathComponent
              while !folder.isEmpty {
                  if result[folder].map({ rank($0) < rank(file.letter) }) ?? true { result[folder] = file.letter }
                  folder = (folder as NSString).deletingLastPathComponent
              }
          }
          return result
      }

      public static func relativePath(_ url: URL, in root: URL) -> String {
          let path = url.standardizedFileURL.path(percentEncoded: false)
          let base = root.standardizedFileURL.path(percentEncoded: false)
          let prefix = base.hasSuffix("/") ? base : base + "/"
          return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : (path == base ? "" : path)
      }

      public static func mention(_ url: URL, in root: URL) -> String { "@" + relativePath(url, in: root) }

      public static func newName(_ base: String, in folder: URL) -> String {
          var name = base, n = 2
          while FileManager.default.fileExists(atPath: folder.appending(path: name).path) { name = "\(base) \(n)"; n += 1 }
          return name
      }
  }
  ```
  `Workspace+Panels.swift`:
  ```swift
  /// Puts "@path" into the composer on screen — Home's or the open chat's.
  public func mention(_ url: URL) {
      guard let project = contextProject else { return }
      pendingMention = FileTree.mention(url, in: project.url)
      mentionRequest += 1
  }
  ```
  (`public internal(set) var pendingMention: String?` and `public internal(set) var mentionRequest = 0` on Workspace.)
  Composer: `.onChange(of: workspace.mentionRequest) { if let m = workspace.pendingMention { let t = text.wrappedValue; text.wrappedValue = t + (t.isEmpty || t.hasSuffix(" ") ? "" : " ") + m + " " }; focus the field }` and `.dropDestination(for: URL.self) { urls, _ in urls.forEach(workspace.mention); return !urls.isEmpty }`.
- [ ] **Step 4: Views.** `FileIcon`:
  ```swift
  /// A symbol and tint for a file or folder, by name.
  enum FileIcon {
      static func symbol(for name: String, isFolder: Bool) -> String {
          if isFolder {
              return switch name {
              case ".git": "arrow.triangle.branch"
              case ".github": "gearshape.2"
              case "docs", "Docs": "book.closed"
              case "apps", "Sources", "src": "shippingbox"
              case "assets", "Resources": "photo.on.rectangle"
              case "scripts": "terminal"
              case "site", "web": "globe"
              case "Tests", "tests": "checkmark.seal"
              default: "folder"
              }
          }
          switch (name as NSString).pathExtension.lowercased() {
          case "swift": return "swift"
          case "md", "markdown", "txt": return "doc.text"
          case "json", "yml", "yaml", "toml", "plist": return "curlybraces"
          case "png", "jpg", "jpeg", "gif", "heic", "svg", "icns": return "photo"
          case "key", "pem", "p12": return "key"
          case "sh", "zsh", "bash": return "terminal"
          default: break
          }
          switch name.lowercased() {
          case "license", "licence", "notice": return "checkmark.shield"
          case ".gitignore", ".gitattributes": return "eye.slash"
          default: return "doc"
          }
      }

      static func tint(for name: String, isFolder: Bool) -> Color {
          if isFolder { return name == ".git" || name == ".github" ? Palette.accent : Palette.textSecondary }
          return (name as NSString).pathExtension == "swift" ? Palette.warning : Palette.textTertiary
      }
  }
  ```
  `ExplorerPanel(workspace:, project:, git: ProjectGit?)`:
  - Header: `MonoLabel(project.name)` + `Image(systemName: "chevron.down")`; trailing `IconButton("doc.badge.plus")` New File, `IconButton("folder.badge.plus")` New Folder, `IconButton("arrow.down.right.and.arrow.up.left")` Collapse All, `IconButton("line.3.horizontal.decrease")` toggles a filter `TextField`.
  - State: `@State expanded: Set<URL>`, `children: [URL: [FileNode]]`, `ignored: Set<String>` (relative paths), `letters`, `selection: URL?`, `preview: URL?`, `renaming: URL?`, `filter: String`.
  - `func load(_ folder: URL) async`: `children[folder] = FileTree.children(of: folder, root: project.url, deleted: deletedPaths)`; `ignored.formUnion(await git?.ignored(children.map(relative)) ?? [])`.
  - `.task(id: git?.generation)`: `letters = FileTree.letters(git?.status ?? GitStatus())`; reload the root and every expanded folder.
  - Rows (recursive `ForEach` over a flattened list `[(node, depth)]` built from `expanded`, filtered by `filter` on name): indent `depth * Space.l`; disclosure chevron for folders (rotates 90° with `Motion.quick`); `Image(systemName: FileIcon.symbol…)` tinted; name in `Typography.body`, coloured by `letters[rel]` (M/R `Palette.warning`, A/U `Palette.success`, D/C `Palette.failure`), `.strikethrough(node.isDeleted)`, `.italic()` and `Palette.textTertiary` when ignored. Selected row on `Palette.hover`.
  - Click: folder → toggle expansion (load on expand); file → `selection = url; preview = url` with `.quickLookPreview($preview)`. Double-click (`.onTapGesture(count: 2)` placed before the single tap) → `NSWorkspace.shared.open(url)`.
  - `.contextMenu`: Reveal in Finder (`activateFileViewerSelecting`), Copy Path (`NSPasteboard` the absolute path), Rename (inline `TextField`, `FileManager.moveItem` on submit), Move to Trash (`FileManager.trashItem`, then a toast "Moved to Trash"), Mention in Chat (`workspace.mention(url)`).
  - `.draggable(node.url)` on file rows.
  - New File / New Folder create `FileTree.newName("untitled" / "untitled folder", in: target)` in the selected folder (or the selected file's folder, or the root), then start renaming it.
- [ ] **Step 5:** `swift test --filter FileTreeTests` → pass; run the app; expand folders, rename, trash, preview, drag a file onto the composer.
- [ ] **Step 6:** Commit `Inspector: the Explorer — a live tree with git colours, preview, rename, trash and mentions.`

### Task 8: Account menu and usage

**Files:**
- Create: `apps/mac/Sources/XBotUI/Account/Identity.swift`, `AccountButton.swift`, `UsageSection.swift`
- Modify: `apps/mac/Sources/XBotUI/Shell/Sidebar.swift` (footer)

**Interfaces:**
- Consumes: `Workspace.usage`, `refreshCodexUsage()`, `claudePlan` (Task 2); `Workspace.page` (Task 6).
- Produces: `@MainActor @Observable final class Identity { static let shared; var name: String; var username: String; var picture: NSImage?; func setName(_:); func setPicture(_: NSImage) }`; `AccountButton(workspace:)`; `Avatar(identity:size:)`.

- [ ] **Step 1: Identity.**
  ```swift
  import AppKit
  import Collaboration
  import Observation
  import XBotCore

  /// Who is using xBot, until it signs in with an Apple ID: the Mac account's name and picture,
  /// unless the person changed them in Edit Profile.
  @MainActor
  @Observable
  final class Identity {
      static let shared = Identity()
      private(set) var name: String
      let username = NSUserName()
      private(set) var picture: NSImage?
      private static let nameKey = "profile.name"
      private static var pictureURL: URL { Store.supportDirectory.appending(path: "profile.png") }

      private init() {
          let account = CBIdentity(name: NSUserName(), authority: .local())
          name = UserDefaults.standard.string(forKey: Self.nameKey) ?? (NSFullUserName().isEmpty ? NSUserName() : NSFullUserName())
          picture = NSImage(contentsOf: Self.pictureURL) ?? account?.image
      }

      func setName(_ value: String) {
          let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return }
          name = trimmed
          UserDefaults.standard.set(trimmed, forKey: Self.nameKey)
      }

      func setPicture(_ image: NSImage) {
          picture = image
          guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
          try? FileManager.default.createDirectory(at: Store.supportDirectory, withIntermediateDirectories: true)
          try? png.write(to: Self.pictureURL)
      }
  }

  /// The person's picture in a circle, or their initials on the accent tint.
  struct Avatar: View {
      let identity: Identity
      let size: CGFloat
      var body: some View {
          Group {
              if let picture = identity.picture {
                  Image(nsImage: picture).resizable().scaledToFill()
              } else {
                  Text(identity.name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined())
                      .font(.system(size: size * 0.4, weight: .semibold))
                      .foregroundStyle(Palette.accent)
                      .frame(maxWidth: .infinity, maxHeight: .infinity)
                      .background(Palette.accentTint)
              }
          }
          .frame(width: size, height: size)
          .clipShape(Circle())
      }
  }
  ```
  (Add `import SwiftUI`. Add `Metrics.avatarSmall: CGFloat = 28`, `Metrics.avatarLarge: CGFloat = 96`, `Metrics.accountMenuWidth: CGFloat = 280`.) Add `.linkedFramework("Collaboration")` is not needed — `import Collaboration` links automatically under SwiftPM on macOS.
- [ ] **Step 2: AccountButton.** Sidebar `footer` becomes `AccountButton(workspace: workspace)`: a `Button` row (`Avatar(identity, Metrics.avatarSmall)`, `Text(identity.name).emphasisText()`, `Spacer`, `Image(systemName: "chevron.up.chevron.down")` tertiary), hover fill, top hairline as today. `.popover(isPresented: $open, arrowEdge: .top)` → `AccountMenu`:
  - Header: avatar 36, name (`emphasisText`), plan line `captionText` tertiary: `[workspace.claudePlan, workspace.usage[.codex]?.limits.plan].compactMap { $0 }.joined(" · ")`, else "Claude Code · Codex".
  - Divider.
  - `UsageSection`: a row button "Usage remaining" + chevron (rotates; `@AppStorage("usageExpanded") var expanded = true`). Expanded: for each of `workspace.availableHarnesses`: `Text(kind.displayName).captionText()` then two rows `HStack { Text("5h"); Spacer; Text(UsageText.remaining(w)).font(Typography.mono); Text(UsageText.resets(w.resetsAt)).captionText().frame(width: 72, alignment: .trailing) }` and "Weekly"; a missing window shows "—"; no data: Claude "Run a turn to see Claude Code's usage.", Codex "No Codex usage yet." Footer: `UsageText.updated(newest updatedAt)` tertiary. Wrapped in `TimelineView(.periodic(from: .now, by: 60))` so the "ago" text stays true.
  - `.task { while !Task.isCancelled { await workspace.refreshCodexUsage(); try? await Task.sleep(for: .seconds(60)) } }`.
  - Divider; menu rows (`SidebarRow` look): "Profile" (`person.crop.circle`) → `workspace.page = .profile; open = false`; "Settings" (`gearshape`) with trailing `MonoLabel("⌘,")` → `openSettings()` (`@Environment(\.openSettings)`).
  - Card: `.frame(width: Metrics.accountMenuWidth)`, `.padding(Space.s)`.
- [ ] **Step 3:** Build and run; open the menu; check usage appears for Claude after one turn and for Codex at once.
- [ ] **Step 4:** Commit `Account menu: your picture and name, usage remaining per agent, Profile and Settings.`

### Task 9: History indexer

**Files:**
- Create: `apps/mac/Sources/XBotCore/History/HistoryTally.swift`, `apps/mac/Sources/XBotCore/History/HistoryIndexer.swift`
- Modify: `Store.swift` (`planRuns()`)
- Test: `apps/mac/Tests/XBotCoreTests/HistoryIndexerTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct FileCarry: Codable, Equatable, Sendable { lastMessageID: String?; taskStart: Date?; codexTotal: Int; cwd: String?; effort: String? }
  public struct HistoryTally: Sendable {
      var days: [DayKey: DayTotal]; var counts: [CountKey: Int]; var projects: [String: ProjectTotal]
      mutating func claude(_ line: String, carry: inout FileCarry, calendar: Calendar)
      mutating func codex(_ line: String, carry: inout FileCarry, calendar: Calendar)
  }
  public struct HistorySummary: Equatable, Sendable {
      public var days: [String: Int]                 // "2026-10-08" → tokens, both agents
      public var tokensByAgent: [HarnessKind: Int]
      public var longestTask: TimeInterval
      public var tools: [NameCount]; public var skills: [NameCount]; public var efforts: [NameCount]
      public var agents: [NameCount]                 // tasks per agent
      public var projects: [ProjectTotal]            // by tokens, descending
      public var found: Set<HarnessKind>             // whose logs exist
  }
  public struct NameCount: Equatable, Sendable { name: String; count: Int }
  public struct ProjectTotal: Equatable, Sendable { path: String; tokens: Int; lastActive: Date }
  public actor HistoryIndexer {
      public init(database: Database, claude: URL = ~/.claude/projects, codex: URL = ~/.codex/sessions, calendar: Calendar = .current)
      public static func live() throws -> HistoryIndexer       // ~/Library/Application Support/xBot/history.sqlite
      public func index()                                       // one incremental pass
      public func summary() -> HistorySummary
  }
  Store.planRuns() throws -> Int
  ```

- [ ] **Step 1: Failing tests**
  ```swift
  import Foundation
  import Testing
  @testable import XBotCore

  @Suite struct HistoryIndexerTests {
      let utc = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

      func user(_ ts: String, _ text: String = "do it") -> String {
          #"{"type":"user","timestamp":"\#(ts)","message":{"role":"user","content":"\#(text)"}}"#
      }
      func toolResult(_ ts: String) -> String {
          #"{"type":"user","timestamp":"\#(ts)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"ok"}]}}"#
      }
      func assistant(_ ts: String, id: String, tokens: Int = 10, tool: String? = nil, skill: String? = nil) -> String {
          let block = tool.map { name in
              #"{"type":"tool_use","id":"t","name":"\#(name)","input":{\#(skill.map { #""skill":"\#($0)""# } ?? "")}}"#
          } ?? #"{"type":"text","text":"hi"}"#
          return #"{"type":"assistant","timestamp":"\#(ts)","effort":"medium","cwd":"/p/xBot","message":{"id":"\#(id)","usage":{"input_tokens":\#(tokens),"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"content":[\#(block)]}}"#
      }

      @Test func aMessageSplitAcrossLinesCountsOnce() {
          var tally = HistoryTally(), carry = FileCarry()
          for line in [user("2026-10-08T10:00:00.000Z"),
                       assistant("2026-10-08T10:00:05.000Z", id: "m1", tokens: 100),
                       assistant("2026-10-08T10:00:06.000Z", id: "m1", tokens: 100, tool: "Read")] {
              tally.claude(line, carry: &carry, calendar: utc)
          }
          let day = tally.days[DayKey(day: "2026-10-08", agent: .claude)]
          #expect(day?.tokens == 100 && day?.tasks == 1)
          #expect(tally.counts[CountKey(kind: .tool, name: "Read")] == 1)
      }

      @Test func taskLengthRunsFromTheQuestionToTheLastReply() {
          var tally = HistoryTally(), carry = FileCarry()
          for line in [user("2026-10-08T10:00:00.000Z"),
                       assistant("2026-10-08T10:00:10.000Z", id: "a"),
                       toolResult("2026-10-08T10:00:20.000Z"),
                       assistant("2026-10-08T10:01:40.000Z", id: "b"),
                       user("2026-10-08T11:00:00.000Z"),
                       assistant("2026-10-08T11:00:05.000Z", id: "c")] {
              tally.claude(line, carry: &carry, calendar: utc)
          }
          let day = tally.days[DayKey(day: "2026-10-08", agent: .claude)]
          #expect(day?.tasks == 2)
          #expect(day?.longestTask == 100)
      }

      @Test func skillsAndEffortsAreCounted() {
          var tally = HistoryTally(), carry = FileCarry()
          tally.claude(user("2026-10-08T10:00:00.000Z"), carry: &carry, calendar: utc)
          tally.claude(assistant("2026-10-08T10:00:01.000Z", id: "a", tool: "Skill", skill: "brainstorming"), carry: &carry, calendar: utc)
          #expect(tally.counts[CountKey(kind: .skill, name: "brainstorming")] == 1)
          #expect(tally.counts[CountKey(kind: .effort, name: "medium")] == 1)
          #expect(tally.projects["/p/xBot"]?.tokens == 10)
      }

      @Test func codexTokensAreTheGrowthOfTheRunningTotal() {
          var tally = HistoryTally(), carry = FileCarry()
          let lines = [
              #"{"timestamp":"2026-10-08T10:00:00.000Z","type":"turn_context","payload":{"cwd":"/p/app","model":"gpt-6.1","effort":"high"}}"#,
              #"{"timestamp":"2026-10-08T10:00:01.000Z","type":"response_item","payload":{"type":"function_call","name":"shell"}}"#,
              #"{"timestamp":"2026-10-08T10:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":500}}}}"#,
              #"{"timestamp":"2026-10-08T10:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":500}}}}"#,
              #"{"timestamp":"2026-10-08T10:00:04.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":800}}}}"#,
              #"{"timestamp":"2026-10-08T10:00:05.000Z","type":"event_msg","payload":{"type":"task_complete","duration_ms":16365}}"#,
          ]
          for line in lines { tally.codex(line, carry: &carry, calendar: utc) }
          let day = tally.days[DayKey(day: "2026-10-08", agent: .codex)]
          #expect(day?.tokens == 800 && day?.tasks == 1 && day?.longestTask == 16.365)
          #expect(tally.counts[CountKey(kind: .tool, name: "shell")] == 1)
          #expect(tally.counts[CountKey(kind: .effort, name: "high")] == 1)
          #expect(tally.projects["/p/app"]?.tokens == 800)
      }

      @Test func aPartialLastLineWaitsForTheNextPass() async throws {
          let root = FileManager.default.temporaryDirectory.appending(path: "hist-\(UUID().uuidString)")
          let claude = root.appending(path: "claude/proj")
          try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
          let file = claude.appending(path: "s.jsonl")
          let first = user("2026-10-08T10:00:00.000Z") + "\n"
          let second = assistant("2026-10-08T10:00:05.000Z", id: "m1", tokens: 42)
          try (first + second.prefix(30)).write(to: file, atomically: true, encoding: .utf8)
          let indexer = try HistoryIndexer(database: Database(), claude: root.appending(path: "claude"),
                                           codex: root.appending(path: "codex"), calendar: utc)
          await indexer.index()
          #expect(await indexer.summary().days["2026-10-08"] == nil)
          try (first + second + "\n").write(to: file, atomically: true, encoding: .utf8)
          await indexer.index()
          await indexer.index()   // a second pass with nothing new adds nothing
          #expect(await indexer.summary().days["2026-10-08"] == 42)
          #expect(await indexer.summary().found == [.claude])
      }
  }
  ```
  And in `StoreTests.swift`:
  ```swift
  @Test func planRunsCountsPlansThatRan() throws {
      let store = Store.inMemory()
      let chat = Chat(projectID: nil, title: "t", harness: .claude, mode: .editFiles)
      try store.save(chat)
      var plan = Plan(summary: "s", status: .finished, note: "", steps: [], added: 0)
      try store.append(ChatMessage(chatID: chat.id, role: .assistant, parts: [.plan(plan)]))
      plan.status = .review
      try store.append(ChatMessage(chatID: chat.id, role: .assistant, parts: [.plan(plan)]))
      #expect(try store.planRuns() == 1)
  }
  ```
  (Use `Plan`'s real initialiser from `Plan.swift`; adjust argument labels to match it.)
- [ ] **Step 2:** `swift test --filter "HistoryIndexerTests|StoreTests"` → compile failure.
- [ ] **Step 3: Implement** `HistoryTally.swift`:
  ```swift
  import Foundation

  public struct DayKey: Hashable, Sendable { public var day: String; public var agent: HarnessKind }
  public struct DayTotal: Equatable, Sendable { public var tokens = 0; public var tasks = 0; public var longestTask: TimeInterval = 0 }
  public struct CountKey: Hashable, Sendable {
      public enum Kind: String, Sendable { case tool, skill, effort }
      public var kind: Kind
      public var name: String
  }
  public struct ProjectTotal: Equatable, Sendable { public var path: String; public var tokens: Int; public var lastActive: Date }
  public struct NameCount: Equatable, Sendable { public var name: String; public var count: Int }

  /// What one log file has left unfinished between passes.
  public struct FileCarry: Codable, Equatable, Sendable {
      /// Claude Code writes one line per content block, each repeating the message's usage.
      public var lastMessageID: String?
      public var taskStart: Date?
      public var taskDay: String?
      /// Codex's running token total for the session.
      public var codexTotal = 0
      public var cwd: String?
      public var effort: String?
  }

  /// The arithmetic of the profile, one log line at a time. No files, no database: those are the
  /// indexer's.
  public struct HistoryTally: Sendable {
      public var days: [DayKey: DayTotal] = [:]
      public var counts: [CountKey: Int] = [:]
      public var projects: [String: ProjectTotal] = [:]

      static let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

      static func day(_ date: Date, _ calendar: Calendar) -> String {
          let c = calendar.dateComponents([.year, .month, .day], from: date)
          return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
      }

      /// Claude Code's `~/.claude/projects/*/*.jsonl`. A person's message starts a task; the task
      /// lasts until the last reply before the next one.
      public mutating func claude(_ line: String, carry: inout FileCarry, calendar: Calendar) {
          guard line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\""),
                let object = jsonObject(line), let stamp = object["timestamp"] as? String,
                let date = try? Self.iso.parse(stamp) else { return }
          let day = Self.day(date, calendar)
          let message = object["message"] as? [String: Any] ?? [:]
          switch object["type"] as? String {
          case "user":
              let content = message["content"]
              let isQuestion = content is String
                  || ((content as? [[String: Any]])?.contains { $0["type"] as? String == "text" } ?? false)
              guard isQuestion, object["isMeta"] as? Bool != true else { return }
              carry.taskStart = date
              carry.taskDay = day
              days[DayKey(day: day, agent: .claude), default: DayTotal()].tasks += 1
          case "assistant":
              if let start = carry.taskStart, let taskDay = carry.taskDay {
                  let key = DayKey(day: taskDay, agent: .claude)
                  days[key, default: DayTotal()].longestTask = max(days[key]?.longestTask ?? 0, date.timeIntervalSince(start))
              }
              let id = message["id"] as? String
              let isNew = id == nil || id != carry.lastMessageID
              carry.lastMessageID = id
              if isNew, let usage = message["usage"] as? [String: Any] {
                  let tokens = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                      .reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
                  days[DayKey(day: day, agent: .claude), default: DayTotal()].tokens += tokens
                  if let cwd = object["cwd"] as? String { addProject(cwd, tokens, date) }
                  if let effort = object["effort"] as? String { counts[CountKey(kind: .effort, name: effort), default: 0] += 1 }
              }
              for block in message["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "tool_use" {
                  guard let name = block["name"] as? String else { continue }
                  counts[CountKey(kind: .tool, name: name), default: 0] += 1
                  if name == "Skill", let skill = (block["input"] as? [String: Any])?["skill"] as? String {
                      counts[CountKey(kind: .skill, name: skill), default: 0] += 1
                  }
              }
          default:
              break
          }
      }

      /// Codex's `~/.codex/sessions/**/rollout-*.jsonl`. Tokens are the growth of the session's
      /// running total, so a repeated count line adds nothing.
      public mutating func codex(_ line: String, carry: inout FileCarry, calendar: Calendar) {
          guard let object = jsonObject(line), let stamp = object["timestamp"] as? String,
                let date = try? Self.iso.parse(stamp),
                let payload = object["payload"] as? [String: Any] else { return }
          let day = Self.day(date, calendar)
          switch (object["type"] as? String, payload["type"] as? String) {
          case ("turn_context", _):
              carry.cwd = payload["cwd"] as? String ?? carry.cwd
              carry.effort = payload["effort"] as? String ?? carry.effort
          case ("response_item", "function_call"), ("response_item", "custom_tool_call"):
              if let name = payload["name"] as? String { counts[CountKey(kind: .tool, name: name), default: 0] += 1 }
          case ("event_msg", "token_count"):
              guard let total = (((payload["info"] as? [String: Any])?["total_token_usage"] as? [String: Any])?["total_tokens"] as? NSNumber)?.intValue else { return }
              let added = total >= carry.codexTotal ? total - carry.codexTotal : total
              carry.codexTotal = total
              guard added > 0 else { return }
              days[DayKey(day: day, agent: .codex), default: DayTotal()].tokens += added
              if let cwd = carry.cwd { addProject(cwd, added, date) }
          case ("event_msg", "task_complete"):
              let key = DayKey(day: day, agent: .codex)
              days[key, default: DayTotal()].tasks += 1
              if let ms = (payload["duration_ms"] as? NSNumber)?.doubleValue {
                  days[key]?.longestTask = max(days[key]?.longestTask ?? 0, ms / 1000)
              }
              if let effort = carry.effort { counts[CountKey(kind: .effort, name: effort), default: 0] += 1 }
          default:
              break
          }
      }

      private mutating func addProject(_ path: String, _ tokens: Int, _ date: Date) {
          var total = projects[path] ?? ProjectTotal(path: path, tokens: 0, lastActive: date)
          total.tokens += tokens
          total.lastActive = max(total.lastActive, date)
          projects[path] = total
      }
  }
  ```
  (`jsonObject` lives in XBotBrain as internal; make it `public` there, or copy the three lines into XBotCore as a fileprivate helper — copy, to keep XBotBrain's surface small.)
  `HistoryIndexer.swift`:
  ```swift
  import Foundation

  public struct HistorySummary: Equatable, Sendable {
      public var days: [String: Int] = [:]
      public var tokensByAgent: [HarnessKind: Int] = [:]
      public var tasksByAgent: [HarnessKind: Int] = [:]
      public var longestTask: TimeInterval = 0
      public var tools: [NameCount] = []
      public var skills: [NameCount] = []
      public var efforts: [NameCount] = []
      public var projects: [ProjectTotal] = []
      public var found: Set<HarnessKind> = []
  }

  /// Reads the agents' own logs into xBot's history, a little at a time: each file is read from
  /// where the last pass stopped, and only whole lines are taken.
  public actor HistoryIndexer {
      private let db: Database
      private let claudeRoot: URL
      private let codexRoot: URL
      private let calendar: Calendar

      public init(database: Database,
                  claude: URL = URL.homeDirectory.appending(path: ".claude/projects"),
                  codex: URL = URL.homeDirectory.appending(path: ".codex/sessions"),
                  calendar: Calendar = .current) throws {
          db = database
          claudeRoot = claude
          codexRoot = codex
          self.calendar = calendar
          try db.execute("CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, offset REAL NOT NULL, carry TEXT NOT NULL)")
          try db.execute("CREATE TABLE IF NOT EXISTS days (day TEXT NOT NULL, agent TEXT NOT NULL, tokens REAL NOT NULL, tasks REAL NOT NULL, longest REAL NOT NULL, PRIMARY KEY (day, agent))")
          try db.execute("CREATE TABLE IF NOT EXISTS counts (kind TEXT NOT NULL, name TEXT NOT NULL, count REAL NOT NULL, PRIMARY KEY (kind, name))")
          try db.execute("CREATE TABLE IF NOT EXISTS projects (path TEXT PRIMARY KEY, tokens REAL NOT NULL, last_active REAL NOT NULL)")
      }

      public static func live() throws -> HistoryIndexer {
          try HistoryIndexer(database: Database(url: Store.supportDirectory.appending(path: "history.sqlite")))
      }

      public func index() {
          for file in files(claudeRoot, depth: 2) { read(file, agent: .claude) }
          for file in files(codexRoot, depth: 4) where file.lastPathComponent.hasPrefix("rollout-") { read(file, agent: .codex) }
      }

      /// `.jsonl` files exactly `depth` folders down (Claude: project/session; Codex: year/month/day/file).
      private func files(_ root: URL, depth: Int) -> [URL] {
          var level = [root]
          for _ in 1..<depth {
              level = level.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
          }
          return level.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
              .filter { $0.pathExtension == "jsonl" }
      }

      private func read(_ url: URL, agent: HarnessKind) {
          let path = url.path
          let row = (try? db.rows("SELECT offset, carry FROM files WHERE path = ?", [.text(path)]))?.first
          var offset: UInt64 = row.flatMap { if case .real(let n) = $0[0] { UInt64(n) } else { nil } } ?? 0
          var carry = row?[1].string.flatMap { try? JSONDecoder().decode(FileCarry.self, from: Data($0.utf8)) } ?? FileCarry()
          guard let handle = try? FileHandle(forReadingFrom: url) else { return }
          defer { try? handle.close() }
          let size = (try? handle.seekToEnd()) ?? 0
          // ponytail: a file that shrank was replaced; read it from the start (its old totals stay).
          if size < offset { offset = 0; carry = FileCarry() }
          guard size > offset else { return }
          try? handle.seek(toOffset: offset)

          var tally = HistoryTally()
          var pending = Data()
          while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty {
              pending.append(chunk)
              guard let lastNewline = pending.lastIndex(of: UInt8(ascii: "\n")) else { continue }
              let complete = pending[pending.startIndex..<lastNewline]
              for line in complete.split(separator: UInt8(ascii: "\n")) {
                  let text = String(decoding: line, as: UTF8.self)
                  if agent == .claude { tally.claude(text, carry: &carry, calendar: calendar) }
                  else { tally.codex(text, carry: &carry, calendar: calendar) }
              }
              offset += UInt64(complete.count + 1)
              pending = Data(pending[(lastNewline + 1)...])
          }
          save(tally, agent: agent, path: path, offset: offset, carry: carry)
      }

      private func save(_ tally: HistoryTally, agent: HarnessKind, path: String, offset: UInt64, carry: FileCarry) {
          do {
              try db.execute("BEGIN")
              for (key, total) in tally.days {
                  try db.execute("""
                      INSERT INTO days (day, agent, tokens, tasks, longest) VALUES (?, ?, ?, ?, ?)
                      ON CONFLICT(day, agent) DO UPDATE SET tokens = tokens + excluded.tokens,
                        tasks = tasks + excluded.tasks, longest = max(longest, excluded.longest)
                      """, [.text(key.day), .text(key.agent.rawValue), .real(Double(total.tokens)),
                            .real(Double(total.tasks)), .real(total.longestTask)])
              }
              for (key, count) in tally.counts {
                  try db.execute("""
                      INSERT INTO counts (kind, name, count) VALUES (?, ?, ?)
                      ON CONFLICT(kind, name) DO UPDATE SET count = count + excluded.count
                      """, [.text(key.kind.rawValue), .text(key.name), .real(Double(count))])
              }
              for project in tally.projects.values {
                  try db.execute("""
                      INSERT INTO projects (path, tokens, last_active) VALUES (?, ?, ?)
                      ON CONFLICT(path) DO UPDATE SET tokens = tokens + excluded.tokens,
                        last_active = max(last_active, excluded.last_active)
                      """, [.text(project.path), .real(Double(project.tokens)), .date(project.lastActive)])
              }
              let json = String(decoding: try JSONEncoder().encode(carry), as: UTF8.self)
              try db.execute("""
                  INSERT INTO files (path, offset, carry) VALUES (?, ?, ?)
                  ON CONFLICT(path) DO UPDATE SET offset = excluded.offset, carry = excluded.carry
                  """, [.text(path), .real(Double(offset)), .text(json)])
              try db.execute("COMMIT")
          } catch {
              try? db.execute("ROLLBACK")
          }
      }

      public func summary() -> HistorySummary {
          var summary = HistorySummary()
          for r in (try? db.rows("SELECT day, agent, tokens, tasks, longest FROM days")) ?? [] {
              guard let day = r[0].string, let agent = r[1].string.flatMap(HarnessKind.init(rawValue:)) else { continue }
              let tokens = Int(r[2].number), tasks = Int(r[3].number)
              if tokens > 0 { summary.days[day, default: 0] += tokens }
              summary.tokensByAgent[agent, default: 0] += tokens
              summary.tasksByAgent[agent, default: 0] += tasks
              summary.longestTask = max(summary.longestTask, r[4].number)
          }
          func counts(_ kind: CountKey.Kind) -> [NameCount] {
              ((try? db.rows("SELECT name, count FROM counts WHERE kind = ? ORDER BY count DESC", [.text(kind.rawValue)])) ?? [])
                  .compactMap { r in r[0].string.map { NameCount(name: $0, count: Int(r[1].number)) } }
          }
          summary.tools = counts(.tool)
          summary.skills = counts(.skill)
          summary.efforts = counts(.effort)
          summary.projects = ((try? db.rows("SELECT path, tokens, last_active FROM projects ORDER BY tokens DESC")) ?? [])
              .compactMap { r in r[0].string.map { ProjectTotal(path: $0, tokens: Int(r[1].number), lastActive: r[2].date) } }
          let found = (try? db.rows("SELECT path FROM files")) ?? []
          if found.contains(where: { $0[0].string?.hasPrefix(claudeRoot.path) == true }) { summary.found.insert(.claude) }
          if found.contains(where: { $0[0].string?.hasPrefix(codexRoot.path) == true }) { summary.found.insert(.codex) }
          return summary
      }
  }
  ```
  Add to `Database.Value`: `var number: Double { if case .real(let n) = self { n } else { 0 } }`.
  Store:
  ```swift
  /// Plans that were run (not just proposed), across every chat.
  public func planRuns() throws -> Int {
      try db.rows("SELECT parts FROM messages WHERE role = 'assistant' AND parts LIKE '%\"plan\"%'").reduce(0) { count, r in
          guard let json = r[0].string, let parts = try? decoder.decode([Part].self, from: Data(json.utf8)) else { return count }
          let ran = parts.contains { if case .plan(let p) = $0 { [.running, .finished, .stopped].contains(p.status) && p.startedAt != nil || p.status == .finished } else { false } }
          return count + (ran ? 1 : 0)
      }
  }
  ```
  (Simplify the predicate to `p.status == .running || p.status == .finished || (p.status == .stopped && p.startedAt != nil)` and keep the test's expectation.)
- [ ] **Step 4:** `swift test --filter "HistoryIndexerTests|StoreTests"` → pass. Then time one real pass: a scratch test (not committed) runs `HistoryIndexer.live()`-equivalent against a temp database and prints the duration and lifetime tokens; expect under a minute for ~1.1 GB.
- [ ] **Step 5:** Commit `History: index Claude Code's and Codex's logs incrementally into xBot's own history.`

### Task 10: Profile maths and the profile page

**Files:**
- Create: `apps/mac/Sources/XBotCore/History/ProfileStats.swift`, `apps/mac/Sources/XBotUI/Profile/ProfileView.swift`, `apps/mac/Sources/XBotUI/Profile/Heatmap.swift`, `apps/mac/Sources/XBotUI/Profile/EditProfileSheet.swift`
- Modify: `Workspace+Panels.swift` (history state), `RootView.swift` (`.profile`), `XBotApp.swift` (indexer at launch and hourly)
- Test: `apps/mac/Tests/XBotCoreTests/ProfileStatsTests.swift`

**Interfaces:**
- Consumes: `HistorySummary`, `HistoryIndexer` (Task 9), `Store.planRuns()`, `Identity`/`Avatar` (Task 8).
- Produces:
  ```swift
  public struct ProfileStats: Equatable, Sendable {
      public enum Mode: String, CaseIterable, Sendable { case daily, weekly, cumulative }
      public var lifetime: Int; public var peak: Int; public var longestStreak: Int; public var currentStreak: Int
      public init(days: [String: Int], today: Date, calendar: Calendar)
      public static func heatmap(_ days: [String: Int], mode: Mode, today: Date, calendar: Calendar) -> [[HeatCell]]  // 53 columns × 7
  }
  public struct HeatCell: Equatable, Sendable { public var date: Date; public var value: Int; public var level: Int /* 0…4 */; public var isFuture: Bool }
  Workspace.history: HistorySummary?; Workspace.planRunCount: Int
  Workspace.indexHistory() async    // runs the indexer, then reloads `history`
  ```

- [ ] **Step 1: Failing tests**
  ```swift
  import Foundation
  import Testing
  @testable import XBotCore

  @Suite struct ProfileStatsTests {
      let utc = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 1; return c }()
      func date(_ s: String) -> Date { try! Date(s + "T12:00:00Z", strategy: .iso8601) }

      @Test func lifetimePeakAndStreaks() {
          let days = ["2026-10-01": 5, "2026-10-02": 50, "2026-10-03": 1, "2026-10-06": 2, "2026-10-07": 3, "2026-10-08": 4]
          let stats = ProfileStats(days: days, today: date("2026-10-08"), calendar: utc)
          #expect(stats.lifetime == 65 && stats.peak == 50)
          #expect(stats.longestStreak == 3 && stats.currentStreak == 3)
      }

      @Test func aStreakSurvivesUntilTheDayIsOver() {
          let stats = ProfileStats(days: ["2026-10-06": 1, "2026-10-07": 1], today: date("2026-10-08"), calendar: utc)
          #expect(stats.currentStreak == 2)
          let broken = ProfileStats(days: ["2026-10-05": 1], today: date("2026-10-08"), calendar: utc)
          #expect(broken.currentStreak == 0)
      }

      @Test func heatmapIs53WeeksEndingThisWeek() {
          let grid = ProfileStats.heatmap(["2026-10-08": 10], mode: .daily, today: date("2026-10-08"), calendar: utc)
          #expect(grid.count == 53 && grid.allSatisfy { $0.count == 7 })
          let last = grid[52]
          // 2026-10-08 is a Thursday: index 4 with Sunday first.
          #expect(last[4].value == 10 && last[4].level == 4)
          #expect(last[5].isFuture && last[6].isFuture)
          #expect(grid[0][0].level == 0)
      }

      @Test func weeklyAndCumulative() {
          let days = ["2026-10-04": 1, "2026-10-05": 2, "2026-10-08": 3]
          let weekly = ProfileStats.heatmap(days, mode: .weekly, today: date("2026-10-08"), calendar: utc)
          #expect(weekly[52][0].value == 6 && weekly[52][4].value == 6)
          let cumulative = ProfileStats.heatmap(days, mode: .cumulative, today: date("2026-10-08"), calendar: utc)
          #expect(cumulative[52][1].value == 3 && cumulative[52][4].value == 6)
      }
  }
  ```
- [ ] **Step 2:** `swift test --filter ProfileStatsTests` → compile failure.
- [ ] **Step 3: Implement** `ProfileStats.swift`:
  ```swift
  import Foundation

  public struct HeatCell: Equatable, Sendable {
      public var date: Date
      public var value: Int
      public var level: Int
      public var isFuture: Bool
  }

  /// The profile's numbers, from tokens per day ("yyyy-MM-dd" → tokens).
  public struct ProfileStats: Equatable, Sendable {
      public enum Mode: String, CaseIterable, Sendable { case daily, weekly, cumulative }

      public var lifetime: Int
      public var peak: Int
      public var longestStreak: Int
      public var currentStreak: Int

      public init(days: [String: Int], today: Date, calendar: Calendar) {
          lifetime = days.values.reduce(0, +)
          peak = days.values.max() ?? 0
          let active = Set(days.filter { $0.value > 0 }.keys)
          var longest = 0, run = 0, previous: Date?
          for key in active.sorted() {
              guard let date = Self.date(key, calendar) else { continue }
              run = previous.map { calendar.dateComponents([.day], from: $0, to: date).day == 1 } == true ? run + 1 : 1
              longest = max(longest, run)
              previous = date
          }
          longestStreak = longest
          // Today not over yet: a streak that reached yesterday still counts.
          var day = calendar.startOfDay(for: today)
          if !active.contains(HistoryTally.day(day, calendar)) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
          var current = 0
          while active.contains(HistoryTally.day(day, calendar)) {
              current += 1
              day = calendar.date(byAdding: .day, value: -1, to: day)!
          }
          currentStreak = current
      }

      static func date(_ key: String, _ calendar: Calendar) -> Date? {
          let parts = key.split(separator: "-").compactMap { Int($0) }
          guard parts.count == 3 else { return nil }
          return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
      }

      /// 53 weeks, oldest first, each the seven days of the calendar's week; the last holds today.
      /// Levels 1–4 are the quartiles of the non-zero values shown.
      public static func heatmap(_ days: [String: Int], mode: Mode, today: Date, calendar: Calendar) -> [[HeatCell]] {
          let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)!.start
          let start = calendar.date(byAdding: .weekOfYear, value: -52, to: thisWeek)!
          let end = calendar.startOfDay(for: today)
          var running = days.filter { key, _ in (date(key, calendar).map { $0 < start } ?? false) }.values.reduce(0, +)
          var grid: [[HeatCell]] = []
          for week in 0..<53 {
              let weekStart = calendar.date(byAdding: .weekOfYear, value: week, to: start)!
              let dates = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: weekStart)! }
              let values = dates.map { days[HistoryTally.day($0, calendar)] ?? 0 }
              let weekTotal = zip(dates, values).filter { $0.0 <= end }.map(\.1).reduce(0, +)
              grid.append(zip(dates, values).map { date, value in
                  let future = date > end
                  if !future { running += value }
                  let shown = future ? 0 : switch mode { case .daily: value; case .weekly: weekTotal; case .cumulative: running }
                  return HeatCell(date: date, value: shown, level: 0, isFuture: future)
              })
          }
          let nonZero = grid.flatMap { $0 }.map(\.value).filter { $0 > 0 }.sorted()
          guard !nonZero.isEmpty else { return grid }
          func quantile(_ q: Double) -> Int { nonZero[min(nonZero.count - 1, Int(Double(nonZero.count - 1) * q))] }
          let cuts = [quantile(0.25), quantile(0.5), quantile(0.75)]
          return grid.map { $0.map { cell in
              var cell = cell
              cell.level = cell.value == 0 ? 0 : 1 + cuts.filter { cell.value > $0 }.count
              return cell
          } }
      }
  }
  ```
  (With one non-zero value all cuts equal it, so the level is 1 — the test expects 4: change the level rule to `cell.value >= nonZero.last! ? 4 : 1 + cuts.filter { cell.value > $0 }.count` so the top value is always the darkest.)
  Workspace (+Panels): `public internal(set) var history: HistorySummary?`, `public internal(set) var planRunCount = 0`, `@ObservationIgnored let indexer: HistoryIndexer?` (new init parameter `indexer: HistoryIndexer? = nil`; the app passes `try? .live()`), and
  ```swift
  public func indexHistory() async {
      guard let indexer else { return }
      await indexer.index()
      history = await indexer.summary()
      planRunCount = attempt { try store.planRuns() } ?? 0
  }
  ```
  XBotApp: `RootView`'s `.task` also runs `while !Task.isCancelled { await workspace.indexHistory(); try? await Task.sleep(for: .seconds(3600)) }`.
- [ ] **Step 4: Views.** `ProfileView(workspace:)` — `ScrollView`, content `frame(maxWidth: Metrics.readingWidth)` centred, `VStack(spacing: Space.xl)`:
  - Top-right `Button("Edit") { editing = true }.buttonStyle(QuietButtonStyle())` → `.sheet` `EditProfileSheet` (name field; "Choose Picture…" with `fileImporter([.image])` → `Identity.shared.setPicture`; Save / Cancel).
  - `Avatar(identity, Metrics.avatarLarge)`, `Text(identity.name).heroText()`, `Text("@\(identity.username)").captionText()` tertiary.
  - Stats strip: one `raisedSurface()` card, `HStack` of five columns divided by 1pt `Palette.hairline` rules; each `VStack { Text(value).titleText(); Text(label).captionText().foregroundStyle(Palette.textTertiary) }`: Lifetime tokens (`compact(stats.lifetime)` → "1.2B", "380M", "45K"), Peak tokens, Longest task (`Duration.seconds(x).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))`), Longest streak ("12 days"), Current streak. A `Image(systemName: "questionmark.circle").help("Input, output and cached tokens, as your agents count them.")` beside Lifetime tokens.
  - Showcase: `Text("Showcase").titleText()`; `HStack` of up to three cards for `history.projects.prefix(3)`: `folder` icon, last path component (`emphasisText`), "\(compact(tokens)) tokens" and "Active \(lastActive.formatted(.relative(presentation: .named)))" captions.
  - Token activity: title + `Picker("", selection: $mode)` segmented (Daily / Weekly / Cumulative) trailing; `Heatmap(cells: ProfileStats.heatmap(history.days, mode:, today: .now, calendar: .current))`.
  - Top tools: `LazyVGrid` 9 columns of 44pt rounded squares (`Palette.inset`, `Radius.medium`) with `ToolLabel` symbols for `history.tools.prefix(9)`, `.help("\(name) · \(count)")`.
  - Insights: rows label/value with hairlines: Most used reasoning (`efforts.first`, with its share "Medium · 37%"); Most used agent (`tasksByAgent` max → displayName); Plan mode runs (`planRunCount`); Skills explored (`skills.count`); Total skills used (`skills.map(\.count).reduce(0,+)`).
  - Missing sources: per agent not in `history.found`, a caption "No \(kind.displayName) history found."; before the first pass a `ProgressView` with "Reading your history…".
  - `.task { await workspace.indexHistory() }`.
  `Heatmap(cells:)`: `HStack(alignment: .top, spacing: 3)` of 53 `VStack(spacing: 3)` columns of 7 `RoundedRectangle(cornerRadius: 2)` 10×10 squares; fill: future → clear, level 0 → `Palette.inset`, else `Palette.heat[level - 1]`; month labels row beneath: a label at each column whose first day starts a month (`Text(date.formatted(.dateTime.month(.abbreviated)))` caption tertiary). `.help("\(value) tokens · \(date)")` per cell. Add `Palette.heat`: four shades of Claude's clay — `dynamic(0xF3D3C6, 0x4A2A20)`, `dynamic(0xE9A98F, 0x7A3F2D)`, `dynamic(0xDF8466, 0xB4583D)`, `dynamic(0xC85F3F, 0xE08A6E)`.
- [ ] **Step 5:** `swift test --filter ProfileStatsTests` → pass; full suite → pass; open the profile in the app and compare with the reference by eye.
- [ ] **Step 6:** Commit `Profile: lifetime tokens, streaks, showcase, the token heatmap, top tools and insights.`

### Task 11: Settings window and draft defaults

**Files:**
- Create: `apps/mac/Sources/XBotUI/Settings/SettingsView.swift`
- Modify: `Workspace.swift` (`defaults` injection), `Workspace+Panels.swift` (`DraftDefaults`), `Backdrop.swift` (respect the setting), `XBotApp.swift` (`Settings` scene; ⌥⌘0)
- Test: `apps/mac/Tests/XBotCoreTests/PanelsTests.swift` (add)

**Interfaces:**
- Produces: `Workspace.defaultHarness: HarnessKind?`, `defaultEffort: Effort?`, `defaultMode: PermissionMode` — persisted in the injected `UserDefaults`, applied to `draft` at init and on set; `SettingsView(workspace:)`; `@AppStorage("showBackdrop")` (default true).

- [ ] **Step 1: Failing test** (append to `PanelsTests`):
  ```swift
  @Test func defaultsShapeTheNextDraftAndAreRemembered() async {
      let defaults = UserDefaults(suiteName: UUID().uuidString)!
      let w = Workspace(store: .inMemory(), inbox: FileManager.default.temporaryDirectory, discover: { [:] }, defaults: defaults)
      w.defaultMode = .readOnly
      w.defaultEffort = .high
      w.defaultHarness = .codex
      #expect(w.draft.mode == .readOnly && w.draft.effort == .high && w.draft.harness == .codex)
      let again = Workspace(store: .inMemory(), inbox: FileManager.default.temporaryDirectory, discover: { [:] }, defaults: defaults)
      #expect(again.draft.mode == .readOnly && again.draft.effort == .high && again.draft.harness == .codex)
  }
  ```
- [ ] **Step 2:** `swift test --filter PanelsTests` → fails (no such properties).
- [ ] **Step 3: Implement** in `Workspace+Panels.swift`:
  ```swift
  extension Workspace {
      public var defaultHarness: HarnessKind? {
          get { defaults.string(forKey: "default.harness").flatMap(HarnessKind.init(rawValue:)) }
          set { defaults.set(newValue?.rawValue, forKey: "default.harness"); draft.harness = newValue; draft.model = nil }
      }
      public var defaultEffort: Effort? {
          get { defaults.string(forKey: "default.effort").flatMap(Effort.init(rawValue:)) }
          set { defaults.set(newValue?.rawValue, forKey: "default.effort"); draft.effort = newValue }
      }
      public var defaultMode: PermissionMode {
          get { defaults.string(forKey: "default.mode").flatMap(PermissionMode.init(rawValue:)) ?? .editFiles }
          set { defaults.set(newValue.rawValue, forKey: "default.mode"); draft.mode = newValue }
      }

      func applyDraftDefaults() {
          draft.harness = defaultHarness
          draft.effort = defaultEffort
          draft.mode = defaultMode
      }
  }
  ```
  Workspace init stores `defaults` (`let defaults: UserDefaults` — mark `@ObservationIgnored`; `UserDefaults` is not Sendable, which is fine on the main actor) and calls `applyDraftDefaults()`. `sendDraft()` after a successful send also re-applies them so the next draft starts from the defaults.
- [ ] **Step 4: Views.** `SettingsView(workspace:)`: `TabView` with `.tabItem` General (`gearshape`), Agents (`cpu`), About (`info.circle`); `.frame(width: 520)`; each tab a `Form` with `.formStyle(.grouped)`.
  - General: `Toggle("Background picture", isOn: $showBackdrop)`; `Picker("Default agent", selection: workspace.defaultHarness)` ("Most recent" = nil + each installed); `Picker("Default reasoning", …)` ("Agent's default" = nil + `Effort.allCases` titles); `Picker("Default permission", …)` (Read only / Edit files / Full access — the Composer's own titles).
  - Agents: per `HarnessKind.allCases`: name; "Found at" path from `(workspace.brains[kind] as? HarnessBrain)?.executable.path` (expose `public func executable(for:) -> URL?` on Workspace) or "Not installed"; "Signed in": Claude `ClaudeAccount.isSignedIn()`, Codex `workspace.usage[.codex] != nil` shown as "Yes" / "Not yet seen"; "Plan" from usage/claudePlan; the two usage windows via `UsageText`; a `Button("Look Again") { Task { await workspace.refreshHarnesses() } }`.
  - About: app icon, version (`Bundle.main` short version + build), `Text(AttributedString(AboutPanel.credits))`.
  `Backdrop`: `@AppStorage("showBackdrop") private var show = true`; render nothing when false.
  XBotApp: add `Settings { SettingsView(workspace: workspace) }`; `@AppStorage("inspectorShown") private var inspectorShown = false` and in `CommandGroup(after: .sidebar)` (or the existing `.windowArrangement` group) `Button(String(localized: "Files and Changes")) { inspectorShown.toggle() }.keyboardShortcut("0", modifiers: [.command, .option])`.
- [ ] **Step 5:** `swift build --build-tests && swift test` → all pass. ⌘, opens Settings; toggles take effect.
- [ ] **Step 6:** Commit `Settings: background, default agent, reasoning and permission; agents; about.`

### Task 12: Docs, verification, install

**Files:**
- Modify: `CHANGELOG.md`, `docs/superpowers/specs/2026-10-08-workspace-panels-design.md` (status line), `CLAUDE.md` only if an invariant changed (none expected).

- [ ] **Step 1:** Full verification: `cd apps/mac && swift build --build-tests && swift test` — read the totals; run `ProjectGitTests` and `HistoryIndexerTests` five times each.
- [ ] **Step 2:** Real-window snapshot of Home with the inspector open (`XBOT_WINDOW_SNAPSHOT=/tmp/panels.png`), look at it; open the account menu and the profile in the running app.
- [ ] **Step 3:** CHANGELOG: an entry under the 2.0.0-dev heading listing the top bar, the inspector (Changes, Explorer, diff), the account menu with usage, the profile, Settings. Spec status → "approved and built (plan …)".
- [ ] **Step 4:** Commit `Docs: workspace panels shipped.`
- [ ] **Step 5:** Install: `swift build -c release --arch arm64`; `XBOT_VERSION=2.0.0-dev XBOT_BUILD_NUMBER=204 scripts/bundle-mac-app.sh`; remove `XBot_XBot*Tests.bundle` from the bundle; `codesign --force --deep --sign -`; move the old `/Applications/XBot.app` to the Trash; `ditto` the new one in; `open` it.
