# Premium UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild xBot's look and feel to the premium-UI spec: neutral surfaces with a sakura accent, a component kit, a quiet sidebar, a hero Home with a context-strip composer, a calmer transcript, and plan cards that read like instruments.

**Architecture:** Logic the UI needs (sidebar grouping, drafts from Home, delete/undo, toasts, reply layout, markdown blocks, git branch) lands in `XBotCore` first, tested. Then `XBotUI` gets a new design system and component kit, and the shell, Home, composer, transcript and plan cards are rebuilt on it. `NavigationSplitView` stays for window behaviour; every visible surface is ours.

**Tech Stack:** Swift 6, SwiftUI (macOS 26), Observation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-08-premium-ui-design.md`

## Global Constraints

- macOS 26, Apple silicon; Swift 6 language mode; no new dependencies.
- Views use tokens only (`Palette`, `Typography`, `Space`, `Radius`, `Metrics`, `Motion`); no raw hex, point size or duration in a view.
- Every user-visible string through `String(localized:)` (product names excepted).
- Accent (`Palette.accent`, sakura) only for: selection marker, send, focus ring, links, Plan chip on. Running state is `Palette.running` (blue).
- Nothing in the UI that does not work (no Notes/Automations/Settings rows yet).
- Motion: springs from `Motion`; honour Reduce Motion / Reduce Transparency in the component.
- Do not edit `README.md`. Do not commit the user's reference screenshots.
- Verification: `cd apps/mac && swift build --build-tests && swift test`; offscreen renders compared with the references.

## Review Focus

1. **A draft aimed at a project that was removed** must send to the Inbox, not fail — Task 1 `aDraftForARemovedProjectGoesToTheInbox`.
2. **Undo after the chat's project was removed** must bring the chat back in the Inbox — Task 1 `undoAfterTheProjectIsGoneRestoresToTheInbox`.
3. **Searching with accents or different case** ("cafe" for "Café") must still find the chat — Task 1 `searchIgnoresCaseAndAccents`.
4. **A git worktree** (`.git` is a file) must still show its branch; a detached HEAD shows none — Task 1 `branchesFromWorktreesAndDetachedHeads`.
5. **A numbered list interrupted by prose** must not merge into one list — Task 2 `proseBetweenListsSplitsThem`.

---

### Task 1: The logic the new UI needs

**Files:**
- Create: `apps/mac/Sources/XBotCore/SidebarModel.swift`, `GitBranch.swift`, `ToastCenter.swift`, `ReplyLayout.swift`, `Workspace+Home.swift`
- Modify: `apps/mac/Sources/XBotCore/Workspace.swift` (new stored state; `deleteChat` returns what it removed), `Workspace+Plan.swift` (finish toast)
- Test: `apps/mac/Tests/XBotCoreTests/HomeTests.swift`, `SidebarModelTests.swift`, `ToastCenterTests.swift`

**Interfaces — Produces:**
- `struct SidebarModel { init(projects: [Project], chats: [Chat], running: Set<UUID>, query: String = "", expanded: Set<UUID> = []); groups: [Group]; recent: [Chat]; inbox: [Chat]; static let chatsPerProject = 5, recentCount = 5 }`, `SidebarModel.Group { project, chats, hidden: Int, isRunning: Bool }`
- `enum GitBranch { static func current(in folder: URL) -> String? }`
- `@MainActor @Observable final class ToastCenter { struct Toast; current: Toast?; init(duration: Duration = .seconds(3), actionDuration: Duration = .seconds(5)); show(_ text: String, systemImage: String? = nil, action: ToastCenter.Action? = nil); performAction(); dismiss() }`, `struct Action { title: String; run: @MainActor () -> Void }`
- `enum ReplySegment: Equatable { text(String), tools([ToolPart]), notice(String), failure(String) }`, `enum ReplyLayout { static func segments(_ parts: [Part]) -> [ReplySegment] }`
- `struct ChatDraft { text, projectID, harness, model, mode, planMode, reviewPlan }`
- `enum Suggestion: CaseIterable { title, subtitle, symbol, prompt, turnsOnPlan }`
- On `Workspace`: `toasts: ToastCenter`, `draft: ChatDraft`, `searchFocusRequest: Int`, `composerFocusRequest: Int`, `runningChatIDs: Set<UUID>`, `isHome: Bool`, `goHome()`, `startDraft(in projectID: UUID?)`, `draftHarness: HarnessKind?`, `sendDraft() -> Bool`, `use(_ suggestion: Suggestion)`, `branch(for projectID: UUID?) -> String?`, `workedFor(_ messageID: UUID, in chatID: UUID) -> TimeInterval?`, `retryLast(in id: UUID) -> Bool`, `deleteChat(_:) -> DeletedChat?`, `restoreChat(_ deleted: DeletedChat)`, `deleteChatWithUndo(_ id: UUID)`, `requestSearchFocus()`

- [ ] **Step 1: Failing tests.**

`SidebarModelTests.swift`

```swift
import Foundation
import Testing
@testable import XBotCore

@Suite struct SidebarModelTests {
    let site = Project(name: "site", path: "/tmp/site")
    let api = Project(name: "api", path: "/tmp/api")

    func chat(_ title: String, in project: Project?, ago: TimeInterval) -> Chat {
        Chat(projectID: project?.id, title: title, harness: .claude, mode: .editFiles,
             updatedAt: Date(timeIntervalSinceNow: -ago))
    }

    @Test func projectsShowTheirFiveNewestChatsAndCountTheRest() {
        let chats = (0..<7).map { chat("c\($0)", in: site, ago: Double($0)) }
        let model = SidebarModel(projects: [site], chats: chats, running: [])
        #expect(model.groups.first?.chats.map(\.title) == ["c0", "c1", "c2", "c3", "c4"])
        #expect(model.groups.first?.hidden == 2)
        let open = SidebarModel(projects: [site], chats: chats, running: [], expanded: [site.id])
        #expect(open.groups.first?.chats.count == 7 && open.groups.first?.hidden == 0)
    }

    @Test func aProjectIsRunningWhenAnyOfItsChatsIs() {
        let busy = chat("busy", in: api, ago: 100)
        let model = SidebarModel(projects: [site, api], chats: (0..<6).map { chat("\($0)", in: api, ago: Double($0)) } + [busy],
                                 running: [busy.id])
        #expect(model.groups.map(\.isRunning) == [false, true])
    }

    @Test func recentIsTheFiveNewestEverywhereAndInboxIsTheLooseOnes() {
        let chats = [chat("a", in: site, ago: 1), chat("b", in: nil, ago: 2), chat("c", in: api, ago: 3),
                     chat("d", in: nil, ago: 4), chat("e", in: site, ago: 5), chat("f", in: site, ago: 6)]
        let model = SidebarModel(projects: [site, api], chats: chats.shuffled(), running: [])
        #expect(model.recent.map(\.title) == ["a", "b", "c", "d", "e"])
        #expect(model.inbox.map(\.title) == ["b", "d"])
    }

    @Test func searchIgnoresCaseAndAccents() {
        let chats = [chat("Café menu", in: site, ago: 1), chat("Billing", in: api, ago: 2)]
        let model = SidebarModel(projects: [site, api], chats: chats, running: [], query: "CAFE")
        #expect(model.recent.map(\.title) == ["Café menu"])
        #expect(model.groups.map(\.project.name) == ["site"])
    }
}
```

`HomeTests.swift`

```swift
import Foundation
import Testing
import XBotBrain
@testable import XBotCore

@MainActor @Suite struct HomeTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "home-\(UUID().uuidString)")

    func workspace(_ brain: SequenceBrain = SequenceBrain([], fallback: [.done]), store: Store = .inMemory()) async -> Workspace {
        let w = Workspace(store: store, inbox: inbox, discover: { [.claude: brain, .codex: SequenceBrain([], fallback: [.done])] })
        await w.refreshHarnesses()
        return w
    }

    func settle(_ w: Workspace, _ id: UUID) async { for _ in 0..<2000 where w.isRunning(id) { await Task.yield() } }

    @Test func homeIsWhereNothingIsSelected() async throws {
        let w = await workspace()
        #expect(w.isHome)
        let chat = try #require(w.newChat(in: nil))
        #expect(!w.isHome)
        w.goHome()
        #expect(w.isHome && w.openChatIDs == [chat.id])
    }

    @Test func aDraftBecomesAChatWithItsSettingsAndIsSent() async throws {
        let brain = SequenceBrain([[.textDelta("hi"), .done]])
        let w = await workspace(brain)
        let project = w.addProject(at: FileManager.default.temporaryDirectory)
        w.startDraft(in: project.id)
        w.draft.harness = .claude
        w.draft.model = "opus"
        w.draft.mode = .readOnly
        w.draft.text = "  Explain this  "
        #expect(w.sendDraft())
        let id = try #require(w.selectedChatID)
        let chat = try #require(w.chat(id))
        #expect(chat.projectID == project.id && chat.model == "opus" && chat.mode == .readOnly)
        #expect(w.draft.text.isEmpty)
        await settle(w, id)
        #expect(w.messages(in: id).first?.parts == [.text("Explain this")])
    }

    @Test func anEmptyDraftDoesNotSend() async {
        let w = await workspace()
        w.draft.text = "   "
        #expect(!w.sendDraft())
        #expect(w.chats.isEmpty && w.isHome)
    }

    @Test func aDraftForARemovedProjectGoesToTheInbox() async throws {
        let w = await workspace()
        let project = w.addProject(at: URL(filePath: "/tmp/gone"))
        w.startDraft(in: project.id)
        w.removeProject(project.id)
        w.draft.text = "hi"
        #expect(w.sendDraft())
        #expect(w.chat(try #require(w.selectedChatID))?.projectID == nil)
    }

    @Test func aSuggestionFillsTheDraftAndMayTurnOnPlan() async {
        let w = await workspace()
        w.use(.explain)
        #expect(w.draft.text == Suggestion.explain.prompt && !w.draft.planMode)
        w.use(.plan)
        #expect(w.draft.planMode)
        #expect(w.composerFocusRequest == 2)
    }

    @Test func workedForRunsFromTheQuestionToTheReply() async throws {
        let w = await workspace(SequenceBrain([[.textDelta("ok"), .done]]))
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("go", in: chat.id)
        await settle(w, chat.id)
        let reply = try #require(w.messages(in: chat.id).last)
        let duration = try #require(w.workedFor(reply.id, in: chat.id))
        #expect(duration >= 0 && duration < 5)
        #expect(w.workedFor(w.messages(in: chat.id)[0].id, in: chat.id) == nil)
    }

    @Test func retryAsksTheLastQuestionAgain() async throws {
        let brain = SequenceBrain([[.failed("limit")], [.textDelta("ok"), .done]])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("Summarise", in: chat.id)
        await settle(w, chat.id)
        #expect(w.retryLast(in: chat.id))
        await settle(w, chat.id)
        #expect(brain.requests.withLock { $0.map(\.prompt) } == ["Summarise", "Summarise"])
    }

    @Test func deletingAChatOffersUndoWhichBringsItBack() async throws {
        let store = Store.inMemory()
        let w = await workspace(SequenceBrain([[.textDelta("ok"), .done]]), store: store)
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("keep me", in: chat.id)
        await settle(w, chat.id)
        w.deleteChatWithUndo(chat.id)
        #expect(w.chat(chat.id) == nil)
        #expect(w.toasts.current?.text == String(localized: "Chat deleted"))
        w.toasts.performAction()
        #expect(w.chat(chat.id) != nil)
        #expect(w.messages(in: chat.id).count == 2)
        #expect(try store.messages(in: chat.id).count == 2)
    }

    @Test func undoAfterTheProjectIsGoneRestoresToTheInbox() async throws {
        let w = await workspace()
        let project = w.addProject(at: URL(filePath: "/tmp/p"))
        let chat = try #require(w.newChat(in: project.id))
        let deleted = try #require(w.deleteChat(chat.id))
        w.removeProject(project.id)
        w.restoreChat(deleted)
        #expect(w.chat(chat.id)?.projectID == nil)
    }

    @Test func aFinishedPlanSaysSo() async throws {
        let brain = SequenceBrain([[.structured(planJSON(["One", "Two"])), .done]],
                                  fallback: [.structured(stepJSON()), .done])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        w.setPlanMode(true, for: chat.id)
        w.setReviewPlan(false, for: chat.id)
        _ = w.send("Go", in: chat.id)
        await settle(w, chat.id)
        #expect(w.toasts.current?.text == String(localized: "Plan finished · 2 steps"))
    }

    @Test func branchesFromWorktreesAndDetachedHeads() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repo = root.appending(path: "repo"), tree = root.appending(path: "tree"), plain = root.appending(path: "plain")
        for dir in [repo.appending(path: ".git"), root.appending(path: "gitdirs/tree"), tree, plain] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try "ref: refs/heads/main\n".write(to: repo.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
        try "gitdir: \(root.path)/gitdirs/tree\n".write(to: tree.appending(path: ".git"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/feature/plan\n".write(to: root.appending(path: "gitdirs/tree/HEAD"), atomically: true, encoding: .utf8)
        #expect(GitBranch.current(in: repo) == "main")
        #expect(GitBranch.current(in: tree) == "feature/plan")
        #expect(GitBranch.current(in: plain) == nil)
        try "0123abcd\n".write(to: repo.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(GitBranch.current(in: repo) == nil)
    }

    @Test func toolsFoldTogetherInAReply() {
        let a = ToolPart(id: "a", name: "Read", summary: "x", output: "1", isError: false)
        let b = ToolPart(id: "b", name: "Bash", summary: "y", output: "", isError: false)
        let segments = ReplyLayout.segments([.text("Look"), .tool(a), .tool(b), .text("Done"), .failure("boom")])
        #expect(segments == [.text("Look"), .tools([a, b]), .text("Done"), .failure("boom")])
    }
}
```

`ToastCenterTests.swift`

```swift
import Testing
@testable import XBotCore

@MainActor @Suite struct ToastCenterTests {
    @Test func toastsQueueAndExpire() async throws {
        let center = ToastCenter(duration: .milliseconds(40), actionDuration: .milliseconds(40))
        center.show("one")
        center.show("two")
        #expect(center.current?.text == "one")
        try await Task.sleep(for: .milliseconds(70))
        #expect(center.current?.text == "two")
        try await Task.sleep(for: .milliseconds(70))
        #expect(center.current == nil)
    }

    @Test func anActionRunsOnceAndMovesOn() {
        let center = ToastCenter()
        var runs = 0
        center.show("Deleted", action: .init(title: "Undo", run: { runs += 1 }))
        center.show("next")
        center.performAction()
        center.performAction()
        #expect(runs == 1)
        #expect(center.current?.text == "next")
    }
}
```

- [ ] **Step 2: Run** → compile errors.

- [ ] **Step 3: Implement.**

`SidebarModel.swift`

```swift
import Foundation

/// What the sidebar shows: projects with their newest chats, Recent, and the Inbox — all narrowed
/// by the search field. Worked out here so the view only draws it.
public struct SidebarModel: Equatable, Sendable {
    public struct Group: Equatable, Sendable, Identifiable {
        public var project: Project
        /// Newest first; at most `chatsPerProject` unless the project is expanded.
        public var chats: [Chat]
        /// Chats in this project not shown.
        public var hidden: Int
        public var isRunning: Bool
        public var id: UUID { project.id }
    }

    public static let chatsPerProject = 5
    public static let recentCount = 5

    public var groups: [Group]
    public var recent: [Chat]
    public var inbox: [Chat]

    public init(
        projects: [Project], chats: [Chat], running: Set<UUID>, query: String = "", expanded: Set<UUID> = []
    ) {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let shown = chats
            .filter { needle.isEmpty || $0.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .sorted { $0.updatedAt > $1.updatedAt }
        groups = projects.compactMap { project in
            let mine = shown.filter { $0.projectID == project.id }
            if !needle.isEmpty && mine.isEmpty { return nil }
            let limit = expanded.contains(project.id) ? mine.count : Self.chatsPerProject
            return Group(
                project: project,
                chats: Array(mine.prefix(limit)),
                hidden: max(0, mine.count - limit),
                isRunning: chats.contains { $0.projectID == project.id && running.contains($0.id) }
            )
        }
        inbox = shown.filter { $0.projectID == nil }
        recent = Array(shown.prefix(Self.recentCount))
    }
}
```

`GitBranch.swift`

```swift
import Foundation

/// The branch checked out in a folder, read straight from `.git/HEAD` — no `git` process.
public enum GitBranch {
    public static func current(in folder: URL) -> String? {
        var gitDir = folder.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue {
            // A worktree: `.git` is a file pointing at the real git directory.
            guard let text = try? String(contentsOf: gitDir, encoding: .utf8),
                  let line = text.split(separator: "\n").first, line.hasPrefix("gitdir: ") else { return nil }
            let path = String(line.dropFirst("gitdir: ".count))
            gitDir = path.hasPrefix("/") ? URL(filePath: path) : folder.appending(path: path)
        }
        guard let head = try? String(contentsOf: gitDir.appending(path: "HEAD"), encoding: .utf8) else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        // A detached HEAD is a commit, not a branch.
        guard trimmed.hasPrefix("ref: refs/heads/") else { return nil }
        return String(trimmed.dropFirst("ref: refs/heads/".count))
    }
}
```

`ToastCenter.swift`

```swift
import Foundation
import Observation

/// Small messages at the bottom of the window, one at a time. A toast with an action (Undo) stays
/// a little longer.
@MainActor
@Observable
public final class ToastCenter {
    public struct Action {
        public var title: String
        public var run: @MainActor () -> Void
        public init(title: String, run: @escaping @MainActor () -> Void) {
            self.title = title
            self.run = run
        }
    }

    public struct Toast: Identifiable {
        public let id = UUID()
        public var text: String
        public var systemImage: String?
        public var action: Action?
    }

    public private(set) var current: Toast?
    private var queue: [Toast] = []
    private var timer: Task<Void, Never>?
    private let duration: Duration
    private let actionDuration: Duration

    public init(duration: Duration = .seconds(3), actionDuration: Duration = .seconds(5)) {
        self.duration = duration
        self.actionDuration = actionDuration
    }

    public func show(_ text: String, systemImage: String? = nil, action: Action? = nil) {
        queue.append(Toast(text: text, systemImage: systemImage, action: action))
        if current == nil { advance() }
    }

    /// Runs the current toast's action, once, and moves on.
    public func performAction() {
        let action = current?.action
        dismiss()
        action?.run()
    }

    public func dismiss() {
        timer?.cancel()
        current = nil
        advance()
    }

    private func advance() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        current = next
        let wait = next.action == nil ? duration : actionDuration
        timer = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, self.current?.id == next.id else { return }
            self.current = nil
            self.advance()
        }
    }
}
```

`ReplyLayout.swift`

```swift
import Foundation

/// A reply as the transcript draws it: text, runs of tools folded into one row, notices, failures.
public enum ReplySegment: Equatable, Sendable {
    case text(String)
    case tools([ToolPart])
    case notice(String)
    case failure(String)
}

public enum ReplyLayout {
    public static func segments(_ parts: [Part]) -> [ReplySegment] {
        var segments: [ReplySegment] = []
        for part in parts {
            switch part {
            case .text(let text): segments.append(.text(text))
            case .tool(let tool):
                if case .tools(var run) = segments.last {
                    run.append(tool)
                    segments[segments.count - 1] = .tools(run)
                } else {
                    segments.append(.tools([tool]))
                }
            case .notice(let text): segments.append(.notice(text))
            case .failure(let reason): segments.append(.failure(reason))
            case .plan: break
            }
        }
        return segments
    }
}
```

`Workspace.swift` — new stored state (beside `problem`):

```swift
    /// Small messages at the bottom of the window.
    public let toasts = ToastCenter()
    /// What Home's composer holds before a chat exists.
    public var draft = ChatDraft()
    /// Bumped to ask the sidebar's search field for focus (⌘K).
    public private(set) var searchFocusRequest = 0
    /// Bumped to ask the composer for focus (a suggestion was chosen).
    public private(set) var composerFocusRequest = 0
```

and `deleteChat` returns what it removed:

```swift
    /// Removes the chat and its messages, and returns them so the removal can be undone.
    @discardableResult
    public func deleteChat(_ id: UUID) -> DeletedChat? {
        guard let chat = chat(id) else { return nil }
        stop(id)
        let messages = transcripts[id] ?? attempt { try store.messages(in: id) } ?? []
        let wasOpen = openChatIDs.contains(id)
        attempt { try store.deleteChat(id) }
        chats.removeAll { $0.id == id }
        forget(id)
        return DeletedChat(chat: chat, messages: messages, wasOpen: wasOpen)
    }
```

`searchFocusRequest`/`composerFocusRequest` are bumped by methods in the extension, so their setters must be module-visible: declare them `public internal(set) var`.

`Workspace+Home.swift`

```swift
import Foundation

/// Home's composer before a chat exists: the text and the settings the chat will start with.
public struct ChatDraft: Equatable, Sendable {
    public var text = ""
    public var projectID: UUID?
    /// Nil: the agent used most recently.
    public var harness: HarnessKind?
    public var model: String?
    public var mode: PermissionMode = .editFiles
    public var planMode = false
    public var reviewPlan = true

    public init() {}
}

/// A deleted chat, kept so Undo can put it back.
public struct DeletedChat: Sendable {
    public let chat: Chat
    public let messages: [ChatMessage]
    public let wasOpen: Bool
}

/// Home's four ways in.
public enum Suggestion: CaseIterable, Sendable {
    case plan, explain, fixBug, writeTests

    public var title: String {
        switch self {
        case .plan: String(localized: "Plan a change")
        case .explain: String(localized: "Explain")
        case .fixBug: String(localized: "Find and fix")
        case .writeTests: String(localized: "Write tests")
        }
    }

    public var subtitle: String {
        switch self {
        case .plan: String(localized: "from an idea")
        case .explain: String(localized: "this project")
        case .fixBug: String(localized: "a bug")
        case .writeTests: String(localized: "for recent changes")
        }
    }

    public var symbol: String {
        switch self {
        case .plan: "list.bullet.clipboard"
        case .explain: "text.magnifyingglass"
        case .fixBug: "ladybug"
        case .writeTests: "checkmark.seal"
        }
    }

    public var prompt: String {
        switch self {
        case .plan: ""
        case .explain: String(localized: "Explain how this project is put together.")
        case .fixBug: String(localized: "Find the bug: ")
        case .writeTests: String(localized: "Write tests for the most recent changes.")
        }
    }

    public var turnsOnPlan: Bool { self == .plan }
}

extension Workspace {
    public var isHome: Bool { selectedChatID == nil }

    public var runningChatIDs: Set<UUID> { Set(turns.keys) }

    public func goHome() { selectedChatID = nil }

    /// Home, aimed at a project (nil: the Inbox).
    public func startDraft(in projectID: UUID?) {
        draft.projectID = projectID
        goHome()
        composerFocusRequest += 1
    }

    public func requestSearchFocus() { searchFocusRequest += 1 }

    /// The agent a new chat would use: the draft's choice if installed, else the most recent, else
    /// the first found.
    public var draftHarness: HarnessKind? {
        let installed = { (kind: HarnessKind?) in kind.flatMap { brains[$0] == nil ? nil : $0 } }
        return installed(draft.harness) ?? installed(chats.first?.harness) ?? availableHarnesses.first
    }

    /// Turns Home's draft into a chat and sends it. False, with the draft untouched, when there is
    /// nothing to send or no agent to send it to.
    @discardableResult
    public func sendDraft() -> Bool {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let harness = draftHarness else { return false }
        // A project removed since the draft was aimed at it: the Inbox, rather than a failed send.
        let projectID = draft.projectID.flatMap { id in projects.contains { $0.id == id } ? id : nil }
        let chat = Chat(
            projectID: projectID, title: String(localized: "New chat"), harness: harness,
            model: draft.harness == harness ? draft.model : nil, mode: draft.mode,
            planMode: draft.planMode, reviewPlan: draft.reviewPlan
        )
        attempt { try store.save(chat) }
        chats.insert(chat, at: 0)
        transcripts[chat.id] = []
        open(chat.id)
        guard send(text, in: chat.id) else { return false }
        draft.text = ""
        return true
    }

    public func use(_ suggestion: Suggestion) {
        draft.text = suggestion.prompt
        if suggestion.turnsOnPlan { draft.planMode = true }
        composerFocusRequest += 1
    }

    public func branch(for projectID: UUID?) -> String? {
        projectID.flatMap { id in projects.first { $0.id == id } }.flatMap { GitBranch.current(in: $0.url) }
    }

    /// How long the agent worked on a reply: from the question before it to the reply.
    public func workedFor(_ messageID: UUID, in chatID: UUID) -> TimeInterval? {
        let list = messages(in: chatID)
        guard let index = list.firstIndex(where: { $0.id == messageID }), list[index].role == .assistant,
              let asked = list[..<index].last(where: { $0.role == .user }) else { return nil }
        return list[index].createdAt.timeIntervalSince(asked.createdAt)
    }

    /// Asks the chat's last question again.
    @discardableResult
    public func retryLast(in id: UUID) -> Bool {
        guard let question = messages(in: id).last(where: { $0.role == .user }) else { return false }
        let text = question.parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n")
        return send(text, in: id)
    }

    public func restoreChat(_ deleted: DeletedChat) {
        guard chat(deleted.chat.id) == nil else { return }
        var chat = deleted.chat
        if let projectID = chat.projectID, !projects.contains(where: { $0.id == projectID }) { chat.projectID = nil }
        attempt {
            try store.save(chat)
            for message in deleted.messages { try store.append(message) }
        }
        chats.append(chat)
        chats.sort { $0.updatedAt > $1.updatedAt }
        transcripts[chat.id] = deleted.messages
        if deleted.wasOpen { open(chat.id) }
    }

    /// Deletes at once and offers Undo, instead of asking first.
    public func deleteChatWithUndo(_ id: UUID) {
        guard let deleted = deleteChat(id) else { return }
        toasts.show(
            String(localized: "Chat deleted"), systemImage: "trash",
            action: .init(title: String(localized: "Undo")) { [weak self] in self?.restoreChat(deleted) }
        )
    }
}
```

`Workspace+Plan.swift` — at the end of `driveSteps`, after the plan is marked finished:

```swift
        let count = storedPlan(messageID, in: chatID)?.steps.count ?? 0
        toasts.show(String(localized: "Plan finished · \(count) steps"), systemImage: "checkmark")
```

- [ ] **Step 4: Run** `swift test --filter "SidebarModelTests|HomeTests|ToastCenterTests|PlanRunTests|WorkspaceTests"` ten times → PASS.
- [ ] **Step 5: Commit** — `"The logic behind the new UI: sidebar, Home drafts, undoable delete, toasts."`

---

### Task 2: Markdown blocks

**Files:** Modify `apps/mac/Sources/XBotCore/MessageMarkdown.swift`; Test `apps/mac/Tests/XBotCoreTests/MessageMarkdownTests.swift`

**Interfaces — Produces:** `MessageMarkdown.Block` gains `.heading(String, level: Int)` and `.list([String], ordered: Bool)`.

- [ ] **Step 1: Failing tests** (add to `MessageMarkdownTests`):

```swift
    @Test func headingsUpToThreeLevels() {
        #expect(MessageMarkdown.blocks(of: "# Title\n## Part\n### Bit\n#hashtag") == [
            .heading("Title", level: 1), .heading("Part", level: 2), .heading("Bit", level: 3),
            .prose("#hashtag"),
        ])
    }

    @Test func bulletsAndNumbersBecomeLists() {
        #expect(MessageMarkdown.blocks(of: "To try it:\n- one\n* two\n\n1. first\n2) second") == [
            .prose("To try it:"), .list(["one", "two"], ordered: false), .list(["first", "second"], ordered: true),
        ])
    }

    @Test func anIndentedLineContinuesItsItem() {
        #expect(MessageMarkdown.blocks(of: "- a long\n  item\n- next") == [.list(["a long item", "next"], ordered: false)])
    }

    @Test func proseBetweenListsSplitsThem() {
        #expect(MessageMarkdown.blocks(of: "1. a\nThen:\n1. b") == [
            .list(["a"], ordered: true), .prose("Then:"), .list(["b"], ordered: true),
        ])
    }

    @Test func aBulletInsideCodeStaysCode() {
        #expect(MessageMarkdown.blocks(of: "```\n- not a list\n```") == [.code("- not a list", language: nil)])
    }
```

- [ ] **Step 2: Run** → FAIL (no such cases).

- [ ] **Step 3: Implement** — `Block` gains the cases (ids `"h:\(level)\(text.hashValue)"`, `"l:\(ordered)\(items.hashValue)"`), and `blocks(of:)` becomes a line machine:

```swift
    public static func blocks(of text: String) -> [Block] {
        var blocks: [Block] = []
        var prose: [String] = []
        var items: [String] = []
        var ordered = false
        var code: [String] = []
        var language: String?
        var inCode = false

        func flushProse() {
            let joined = prose.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(.prose(joined)) }
            prose = []
        }
        func flushList() {
            if !items.isEmpty { blocks.append(.list(items, ordered: ordered)) }
            items = []
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(code.joined(separator: "\n"), language: language))
                    code = []
                    language = nil
                    inCode = false
                } else {
                    flushProse()
                    flushList()
                    let tag = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    language = tag.isEmpty ? nil : tag
                    inCode = true
                }
                continue
            }
            if inCode { code.append(line); continue }
            if let heading = line.wholeMatch(of: /(#{1,3}) +(.+)/) {
                flushProse()
                flushList()
                blocks.append(.heading(String(heading.2), level: heading.1.count))
                continue
            }
            if let item = listItem(line) {
                flushProse()
                if !items.isEmpty && item.ordered != ordered { flushList() }
                ordered = item.ordered
                items.append(item.text)
                continue
            }
            if !items.isEmpty {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { flushList(); continue }
                if line.hasPrefix("  ") || line.hasPrefix("\t") {
                    items[items.count - 1] += " " + trimmed
                    continue
                }
                flushList()
            }
            prose.append(line)
        }

        /*
         * Whatever is still open when the text runs out.
         *
         * While a reply streams, the closing fence has simply not arrived yet. Treating the tail as
         * prose until it does would redraw the whole block the moment it lands, so an unterminated
         * fence is code from the first line.
         */
        if inCode {
            blocks.append(.code(code.joined(separator: "\n"), language: language))
        } else {
            flushProse()
            flushList()
        }
        return blocks
    }

    private static func listItem(_ line: String) -> (ordered: Bool, text: String)? {
        if let match = line.wholeMatch(of: /\s{0,3}[-*•] +(.+)/) { return (false, String(match.1)) }
        if let match = line.wholeMatch(of: /\s{0,3}\d+[.)] +(.+)/) { return (true, String(match.1)) }
        return nil
    }
```

- [ ] **Step 4: Run** `swift test --filter MessageMarkdownTests` → PASS (old cases too).
- [ ] **Step 5: Commit** — `"Replies get headings and lists."`

---

### Task 3: Design system and component kit

**Files:**
- Rewrite: `apps/mac/Sources/XBotUI/DesignSystem/Palette.swift`, `Typography.swift`, `Space.swift`
- Create: `apps/mac/Sources/XBotUI/DesignSystem/Depth.swift`
- Delete: `DesignSystem/AuroraBackground.swift`, `DesignSystem/Materials.swift`
- Create: `apps/mac/Sources/XBotUI/Components/Card.swift`, `Chip.swift`, `StatusPill.swift`, `Buttons.swift`, `SidebarRow.swift`, `ToastView.swift`
- Modify: every existing view, mechanically, to the new token names; `CodeBlockView.swift` to `InsetPanel` styling

**Interfaces — Produces:** tokens and components named in the spec: `Palette.{window, sidebar, raised, inset, hairline, hover, textPrimary, textSecondary, textTertiary, accent, accentTint, running, runningTint, success, successTint, failure, failureTint, warning, warningTint, codeKeyword, codeString, codeComment, codeNumber}`, `Palette.agent(_:)`; `Typography.{hero, title, body, reading, emphasis, chip, caption, label, mono}` with `heroText()`, `titleText()`, `bodyText()`, `readingText()`, `emphasisText()`, `captionText()`, `labelText()`; `Radius.{small 6, medium 10, large 14}`; `Metrics.{sidebarWidth 200...320, sidebarIdealWidth 240, topBar 44, row 28, iconButton 28, sendButton 30, composerWidth 680, readingWidth 720, minimumWindow, defaultWindow, stepIndent, progressHeight, toolOutputMaxHeight}`; `cardShadow()`, `floatingShadow()`; `Card`, `InsetPanel`, `Chip`, `StatusPill`/`PillState`, `MonoLabel`, `IconButton`, `PrimaryButtonStyle`, `QuietButtonStyle`, `SidebarRow`, `ToastHost`.

Views get no unit tests; this task is verified by building, the whole suite, and a component render.

- [ ] **Step 1: `Palette.swift`**

```swift
import AppKit
import SwiftUI

/// Semantic colour. Neutral surfaces; one accent (sakura), used only for selection, send, focus,
/// links and the Plan chip; state colours only where state is meant. Every token resolves in light
/// and dark, and no view ever names a value. See docs/superpowers/specs/2026-10-08-premium-ui-design.md.
public enum Palette {
    // Surfaces
    public static let window = dynamic(0xF7F7F5, 0x1E1E1E)
    public static let sidebar = dynamic(0xF0F0EE, 0x191919)
    public static let raised = dynamic(0xFFFFFF, 0x262626)
    public static let inset = dynamic(0xF2F2F0, 0x202020)
    public static let hairline = dynamic(0x000000, 0xFFFFFF, alpha: (0.08, 0.08))
    public static let hover = dynamic(0x000000, 0xFFFFFF, alpha: (0.04, 0.05))

    // Text
    public static let textPrimary = dynamic(0x1A1A1A, 0xECECEC)
    public static let textSecondary = dynamic(0x1A1A1A, 0xECECEC, alpha: (0.6, 0.6))
    public static let textTertiary = dynamic(0x1A1A1A, 0xECECEC, alpha: (0.4, 0.4))
    /// Text on `textPrimary` — the primary button, toasts.
    public static let textInverse = dynamic(0xFFFFFF, 0x1A1A1A)

    // Accent and state, each with the tint its pill sits on
    public static let accent = dynamic(0xB65E8C, 0xD08AB0)
    public static let accentTint = dynamic(0xB65E8C, 0xD08AB0, alpha: (0.12, 0.18))
    public static let running = dynamic(0x2C6FD1, 0x4C90EE)
    public static let runningTint = dynamic(0x2C6FD1, 0x4C90EE, alpha: (0.12, 0.18))
    public static let success = dynamic(0x2F9E5B, 0x4CB876)
    public static let successTint = dynamic(0x2F9E5B, 0x4CB876, alpha: (0.12, 0.18))
    public static let failure = dynamic(0xD0453E, 0xF07A72)
    public static let failureTint = dynamic(0xD0453E, 0xF07A72, alpha: (0.10, 0.16))
    public static let warning = dynamic(0xC98A1E, 0xE8A845)
    public static let warningTint = dynamic(0xC98A1E, 0xE8A845, alpha: (0.12, 0.18))

    // Code
    public static let codeKeyword = dynamic(0xA2456F, 0xE0A0C0)
    public static let codeString = dynamic(0x2F7D4F, 0x8CC8A0)
    public static let codeComment = dynamic(0x8A8A85, 0x7A7A75)
    public static let codeNumber = dynamic(0xB86A1E, 0xE0A060)

    /// Each agent's mark: Claude Code's clay, Codex in ink.
    public static func agent(_ kind: HarnessKind) -> Color {
        switch kind {
        case .claude: claude
        case .codex: textPrimary
        }
    }

    private static let claude = dynamic(0xD97757, 0xE08A6E)

    private static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: (CGFloat, CGFloat) = (1, 1)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? alpha.1 : alpha.0)
        })
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
```
(`XBotUI` sees `HarnessKind` through `XBotCore`'s re-export of `XBotBrain`; add `import XBotCore`.)

- [ ] **Step 2: `Typography.swift`**

```swift
import SwiftUI

/// The type scale: SF Pro, with SF Mono for metadata. Weight does the hierarchy; sizes stay close.
public enum Typography {
    public static let hero = Font.system(size: 26, weight: .semibold)
    public static let title = Font.system(size: 15, weight: .semibold)
    public static let body = Font.system(size: 13)
    public static let reading = Font.system(size: 13.5)
    public static let emphasis = Font.system(size: 13, weight: .medium)
    public static let chip = Font.system(size: 12, weight: .medium)
    public static let caption = Font.system(size: 11)
    public static let label = Font.system(size: 10, weight: .medium, design: .monospaced)
    public static let mono = Font.system(size: 12, design: .monospaced)
}

extension View {
    /// Type plus its tracking, together, because they are not separable choices.
    public func xbotFont(_ font: Font, tracking: CGFloat) -> some View {
        self.font(font).tracking(tracking)
    }

    public func heroText() -> some View { xbotFont(Typography.hero, tracking: -0.4) }
    public func titleText() -> some View { xbotFont(Typography.title, tracking: -0.2) }
    public func bodyText() -> some View { xbotFont(Typography.body, tracking: 0) }
    public func emphasisText() -> some View { xbotFont(Typography.emphasis, tracking: 0) }
    public func captionText() -> some View { xbotFont(Typography.caption, tracking: 0.1) }
    /// Replies: a touch larger, with air between lines.
    public func readingText() -> some View { xbotFont(Typography.reading, tracking: 0).lineSpacing(4) }
    /// Metadata: "3 OF 7 DONE", "● CONNECTED".
    public func labelText() -> some View { xbotFont(Typography.label, tracking: 0.6).textCase(.uppercase) }
}
```

- [ ] **Step 3: `Space.swift`** — `Space` unchanged; `Radius` = `small 6, medium 10, large 14`; `Metrics`:

```swift
public enum Metrics {
    public static let sidebarWidth: ClosedRange<CGFloat> = 200...320
    public static let sidebarIdealWidth: CGFloat = 240
    /// Room for the traffic lights above the sidebar's header.
    public static let titleBarInset: CGFloat = 38
    public static let topBar: CGFloat = 44
    public static let row: CGFloat = 28
    public static let iconButton: CGFloat = 28
    public static let chipHeight: CGFloat = 26
    public static let sendButton: CGFloat = 30
    public static let composerWidth: CGFloat = 680
    /// A transcript line longer than this is hard to read; wider windows add margin, not width.
    public static let readingWidth: CGFloat = 720
    public static let tabMaxWidth: CGFloat = 180
    public static let suggestionHeight: CGFloat = 96
    public static let minimumWindow = CGSize(width: 900, height: 600)
    public static let defaultWindow = CGSize(width: 1280, height: 820)
    public static let toolOutputMaxHeight: CGFloat = 240
    /// A plan step's tool rows sit under its title, past the status icon.
    public static let stepIndent: CGFloat = 22
    public static let progressHeight: CGFloat = 2
    public static let dot: CGFloat = 6
}
```

- [ ] **Step 4: `Depth.swift`**

```swift
import SwiftUI

/// Two depths: a card on the page, and something floating over it.
extension View {
    public func cardShadow() -> some View {
        shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
    }

    public func floatingShadow() -> some View {
        shadow(color: .black.opacity(0.10), radius: 12, y: 8)
    }

    /// The raised card surface: fill, hairline, shadow.
    public func raisedSurface(radius: CGFloat = Radius.large) -> some View {
        background(Palette.raised, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.hairline))
    }
}
```

- [ ] **Step 5: Components.**

`Card.swift`

```swift
import SwiftUI

/// A titled card: title, a quiet subtitle and mono metadata on one line; a body; an optional footer.
public struct Card<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    let meta: String?
    let content: Content
    let footer: Footer

    public init(
        title: String, subtitle: String? = nil, meta: String? = nil,
        @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.content = content()
        self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(title).emphasisText().foregroundStyle(Palette.textPrimary)
                if let subtitle { Text(subtitle).captionText().foregroundStyle(Palette.textTertiary) }
                Spacer(minLength: Space.s)
                if let meta { MonoLabel(meta) }
            }
            .padding(.horizontal, Space.m)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            content
                .padding(.horizontal, Space.xs)
            footer
        }
        .raisedSurface()
        .cardShadow()
    }
}

extension Card where Footer == EmptyView {
    public init(title: String, subtitle: String? = nil, meta: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, meta: meta, content: content, footer: { EmptyView() })
    }
}

/// The footer row of a card: mono status on the left, actions on the right.
public struct CardFooter<Actions: View>: View {
    let status: String
    let actions: Actions

    public init(_ status: String, @ViewBuilder actions: () -> Actions) {
        self.status = status
        self.actions = actions()
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            MonoLabel(status)
            Spacer()
            actions
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }
}

/// A panel inside a card: lists, illustrations, code.
public struct InsetPanel<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }
}

/// Metadata in small mono capitals: "6 STEPS", "READ-ONLY PLANNING".
public struct MonoLabel: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text).labelText().foregroundStyle(Palette.textTertiary)
    }
}
```

`StatusPill.swift`

```swift
import SwiftUI

public enum PillState: Sendable {
    case neutral, running, success, failure, warning, accent

    var color: Color {
        switch self {
        case .neutral: Palette.textSecondary
        case .running: Palette.running
        case .success: Palette.success
        case .failure: Palette.failure
        case .warning: Palette.warning
        case .accent: Palette.accent
        }
    }

    var tint: Color {
        switch self {
        case .neutral: Palette.hover
        case .running: Palette.runningTint
        case .success: Palette.successTint
        case .failure: Palette.failureTint
        case .warning: Palette.warningTint
        case .accent: Palette.accentTint
        }
    }
}

/// "● CONNECTED": a dot and mono capitals on a tint of the state's colour.
public struct StatusPill: View {
    let state: PillState
    let text: String

    public init(_ state: PillState, _ text: String) {
        self.state = state
        self.text = text
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            Circle().fill(state.color).frame(width: Metrics.dot - 1, height: Metrics.dot - 1)
            Text(text).labelText()
        }
        .foregroundStyle(state.color)
        .padding(.horizontal, Space.s - 2)
        .padding(.vertical, Space.xxs)
        .background(state.tint, in: Capsule())
    }
}
```

`Chip.swift`

```swift
import SwiftUI

/// A quiet rounded control for the composer: "● Claude Code · Opus ⌄", "✎ Can edit ⌄", "Plan".
/// Used as a Menu's label, or alone as a toggle.
public struct Chip: View {
    let title: String
    var systemImage: String?
    var detail: String?
    var dot: Color?
    var isOn = false
    var showsChevron = false
    @State private var hovering = false

    public init(
        _ title: String, systemImage: String? = nil, detail: String? = nil, dot: Color? = nil,
        isOn: Bool = false, showsChevron: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.dot = dot
        self.isOn = isOn
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            if let dot { Circle().fill(dot).frame(width: Metrics.dot, height: Metrics.dot) }
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
            if let detail { Text(detail).foregroundStyle(isOn ? Palette.accent : Palette.textTertiary) }
            if showsChevron {
                Image(systemName: "chevron.down").imageScale(.small).foregroundStyle(Palette.textTertiary)
            }
        }
        .font(Typography.chip)
        .foregroundStyle(isOn ? Palette.accent : Palette.textSecondary)
        .padding(.horizontal, Space.s)
        .frame(height: Metrics.chipHeight)
        .background(
            isOn ? Palette.accentTint : (hovering ? Palette.hover : .clear),
            in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: isOn)
    }
}
```

`Buttons.swift`

```swift
import SwiftUI

/// The one strong action on a surface: a black capsule (white in dark mode).
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.chip)
            .foregroundStyle(Palette.textInverse)
            .padding(.horizontal, Space.m)
            .frame(height: Metrics.chipHeight)
            .background(Palette.textPrimary.opacity(isEnabled ? 1 : 0.3), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.1, bounce: 0), value: configuration.isPressed)
    }
}

/// A secondary action: text that gets a fill on hover.
public struct QuietButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        QuietLabel(configuration: configuration)
    }

    private struct QuietLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Typography.chip)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Space.s)
                .frame(height: Metrics.chipHeight)
                .background(hovering ? Palette.hover : .clear, in: Capsule())
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(duration: 0.1, bounce: 0), value: configuration.isPressed)
        }
    }
}

/// A 28pt symbol button with a hover fill.
public struct IconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    public init(_ systemImage: String, help: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Typography.emphasis)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: Metrics.iconButton, height: Metrics.iconButton)
                .background(hovering ? Palette.hover : .clear,
                            in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(XBotButtonStyle())
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
```

`SidebarRow.swift`

```swift
import SwiftUI

/// A sidebar row: icon, title, something trailing. Selection is a raised fill, not a colour.
public struct SidebarRow<Trailing: View>: View {
    let systemImage: String?
    let title: String
    let isSelected: Bool
    let trailing: Trailing
    @State private var hovering = false

    public init(_ title: String, systemImage: String? = nil, isSelected: Bool = false,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .frame(width: Space.l)
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textTertiary)
            }
            Text(title)
                .font(isSelected ? Typography.emphasis : Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Space.xs)
            trailing
        }
        .padding(.horizontal, Space.s)
        .frame(height: Metrics.row)
        .background(
            isSelected ? Palette.raised : (hovering ? Palette.hover : .clear),
            in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous).strokeBorder(Palette.hairline)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

extension SidebarRow where Trailing == EmptyView {
    public init(_ title: String, systemImage: String? = nil, isSelected: Bool = false) {
        self.init(title, systemImage: systemImage, isSelected: isSelected) { EmptyView() }
    }
}
```

`ToastView.swift`

```swift
import SwiftUI
import XBotCore

/// The current toast, bottom centre: a dark capsule that slides up and fades.
public struct ToastHost: View {
    let center: ToastCenter

    public init(center: ToastCenter) { self.center = center }

    public var body: some View {
        ZStack {
            if let toast = center.current {
                HStack(spacing: Space.s) {
                    if let symbol = toast.systemImage { Image(systemName: symbol) }
                    Text(toast.text)
                    if let action = toast.action {
                        Button(action.title) { center.performAction() }
                            .buttonStyle(.plain)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.accent)
                    }
                }
                .font(Typography.chip)
                .foregroundStyle(Palette.textInverse)
                .padding(.horizontal, Space.m)
                .frame(height: Metrics.iconButton + Space.xs)
                .background(Palette.textPrimary, in: Capsule())
                .floatingShadow()
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .padding(.bottom, Space.xl)
        .motion(Motion.panel, value: center.current?.id)
    }
}
```

`CodeBlockView` — background `Palette.inset` with `Radius.medium` and no border; `stateRunning` → `success` for the "Copied" tint.

- [ ] **Step 6: Mechanical renames** across `XBotUI` and `XBotApp`:

| Old | New |
| --- | --- |
| `Palette.windowBackground` | `Palette.window` |
| `Palette.elevatedSurface` | `Palette.raised` |
| `Palette.panelBackground`, `Palette.codeBackground` | `Palette.inset` |
| `Palette.separator` | `Palette.hairline` |
| `Palette.stateFailed` | `Palette.failure` |
| `Palette.stateRunning` | `Palette.running` |
| `Palette.accent` in `Chat/Plan/*` (it meant "running") | `Palette.running` — do this first |
| `Palette.bubbleOutgoing` / `bubbleOutgoingText` | `Palette.raised` / `Palette.textPrimary` |
| `.bodyEmphasis()` | `.emphasisText()` |
| `.sectionTitle()` / `.displayTitle()` | `.titleText()` / `.heroText()` |
| `Typography.bodyEmphasis` | `Typography.emphasis` |
| `Metrics.tabWidth` | `Metrics.tabMaxWidth` |

- [ ] **Step 7: Build and test.** `swift build --build-tests && swift test` → all pass. Render a scratch gallery of the components (Card with InsetPanel and pills, chips on and off, buttons, sidebar rows, a toast) in light and dark; look at it; delete the scratch.
- [ ] **Step 8: Commit** — `"A neutral design system with one accent, and the component kit."`

---

### Task 4: The window and the sidebar

**Files:**
- Rewrite: `apps/mac/Sources/XBotUI/Shell/RootView.swift`, `Shell/Sidebar.swift`
- Create: `apps/mac/Sources/XBotUI/Shell/TopBar.swift`
- Delete: `apps/mac/Sources/XBotUI/Chat/ChatTabs.swift`
- Modify: `apps/mac/Sources/XBotApp/XBotApp.swift` (hidden title bar, ⌘K, ⌘N → Home, sidebar commands)

**Interfaces — Consumes:** Task 1's `Workspace` API and `SidebarModel`; Task 3's kit. **Produces:** `RootView(workspace:)`; `HomeView` is referenced here and created in Task 5 (create a placeholder `HomeView` returning the old `EmptyState` until then, so this task builds).

- [ ] **Step 1: `RootView.swift`**

```swift
import SwiftUI
import XBotCore

/// The window: the sidebar, a top bar of open chats, and Home or a chat.
public struct RootView: View {
    @Bindable private var workspace: Workspace
    @State private var addingProject = false
    @Namespace private var composer

    public init(workspace: Workspace) { self.workspace = workspace }

    public var body: some View {
        NavigationSplitView {
            Sidebar(workspace: workspace, addProject: { addingProject = true })
                .navigationSplitViewColumnWidth(
                    min: Metrics.sidebarWidth.lowerBound, ideal: Metrics.sidebarIdealWidth,
                    max: Metrics.sidebarWidth.upperBound
                )
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                TopBar(workspace: workspace)
                if let problem = workspace.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .captionText()
                        .foregroundStyle(Palette.failure)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.s)
                        .background(Palette.failureTint)
                }
                ZStack {
                    if let id = workspace.selectedChatID, let chat = workspace.chat(id) {
                        ChatView(workspace: workspace, chat: chat, composer: composer).id(chat.id)
                    } else {
                        HomeView(workspace: workspace, composer: composer, addProject: { addingProject = true })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Palette.window)
            .toolbar(.hidden, for: .windowToolbar)
        }
        .overlay(alignment: .bottom) { ToastHost(center: workspace.toasts) }
        .fileImporter(isPresented: $addingProject, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let project = workspace.addProject(at: url)
                workspace.startDraft(in: project.id)
            }
        }
        .task { await workspace.refreshHarnesses() }
    }
}
```

- [ ] **Step 2: `TopBar.swift`**

```swift
import SwiftUI
import XBotCore

/// Open chats as pill tabs, and where the selected chat works — the window's drag area too.
struct TopBar: View {
    let workspace: Workspace

    var body: some View {
        HStack(spacing: Space.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xxs) {
                    ForEach(workspace.openChatIDs, id: \.self) { id in
                        if let chat = workspace.chat(id) { Tab(workspace: workspace, chat: chat) }
                    }
                }
            }
            Spacer(minLength: Space.m)
            if let id = workspace.selectedChatID, let chat = workspace.chat(id) {
                MonoLabel(context(for: chat))
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: Metrics.topBar)
        .background(Palette.window.gesture(WindowDragGesture()))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    /// "XBOT › MASTER", or "INBOX".
    private func context(for chat: Chat) -> String {
        guard let project = workspace.projects.first(where: { $0.id == chat.projectID }) else {
            return String(localized: "Inbox")
        }
        return [project.name, workspace.branch(for: project.id)].compactMap { $0 }.joined(separator: " › ")
    }

    private struct Tab: View {
        let workspace: Workspace
        let chat: Chat
        @State private var hovering = false

        var body: some View {
            let selected = workspace.selectedChatID == chat.id
            HStack(spacing: Space.xs) {
                if workspace.isRunning(chat.id) {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().fill(Palette.agent(chat.harness)).frame(width: Metrics.dot, height: Metrics.dot)
                }
                Text(chat.title).font(Typography.chip).lineLimit(1)
                    .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                if hovering || selected {
                    Button { workspace.close(chat.id) } label: {
                        Image(systemName: "xmark").imageScale(.small).foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Close tab"))
                }
            }
            .padding(.horizontal, Space.s + 2)
            .frame(height: Metrics.chipHeight)
            .frame(maxWidth: Metrics.tabMaxWidth)
            .background(selected ? Palette.raised : (hovering ? Palette.hover : .clear), in: Capsule())
            .overlay { if selected { Capsule().strokeBorder(Palette.hairline) } }
            .contentShape(Capsule())
            .onTapGesture { workspace.open(chat.id) }
            .onHover { hovering = $0 }
            .motion(Motion.quick, value: selected)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(chat.title)
        }
    }
}
```

- [ ] **Step 3: `Sidebar.swift`**

```swift
import SwiftUI
import XBotCore

/// Search, Home and Inbox, projects with their chats, Recent, and the agents found.
struct Sidebar: View {
    let workspace: Workspace
    let addProject: () -> Void
    @State private var query = ""
    @State private var expanded: Set<UUID> = []
    @State private var collapsed: Set<UUID> = []
    @State private var inboxOpen = true
    @State private var renaming: UUID?
    @State private var renameText = ""
    @FocusState private var searchFocused: Bool

    private var model: SidebarModel {
        SidebarModel(projects: workspace.projects, chats: workspace.chats, running: workspace.runningChatIDs,
                     query: query, expanded: expanded)
    }

    var body: some View {
        let model = model
        VStack(alignment: .leading, spacing: Space.s) {
            header
            search
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    Button { workspace.goHome() } label: {
                        SidebarRow(String(localized: "Home"), systemImage: "house", isSelected: workspace.isHome)
                    }
                    .buttonStyle(.plain)
                    Button { inboxOpen.toggle() } label: {
                        SidebarRow(String(localized: "Inbox"), systemImage: "tray") {
                            if !model.inbox.isEmpty { MonoLabel("\(model.inbox.count)") }
                        }
                    }
                    .buttonStyle(.plain)
                    if inboxOpen || !query.isEmpty {
                        ForEach(model.inbox.prefix(SidebarModel.chatsPerProject)) { chatRow($0) }
                    }

                    sectionHeader(String(localized: "Projects"), add: addProject)
                    if model.groups.isEmpty && query.isEmpty {
                        Button(action: addProject) {
                            SidebarRow(String(localized: "Add a folder"), systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(model.groups) { group in projectSection(group) }

                    if !model.recent.isEmpty {
                        sectionHeader(String(localized: "Recent"), add: nil)
                        ForEach(model.recent) { chatRow($0, indent: false) }
                    }
                }
                .padding(.horizontal, Space.s)
            }
            .scrollIndicators(.never)
            footer
        }
        .padding(.top, Metrics.titleBarInset)
        .background(Palette.sidebar)
        .onChange(of: workspace.searchFocusRequest) { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            AppMarkView(size: Space.l + Space.xxs)
            Text(verbatim: "xBot").emphasisText()
            Spacer()
            IconButton("square.and.pencil", help: String(localized: "New chat (⌘N)")) { workspace.startDraft(in: nil) }
        }
        .padding(.horizontal, Space.m)
    }

    private var search: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.textTertiary)
            TextField(String(localized: "Search"), text: $query)
                .textFieldStyle(.plain)
                .bodyText()
                .focused($searchFocused)
                .onExitCommand { query = ""; searchFocused = false }
            if query.isEmpty { MonoLabel("⌘K") }
        }
        .padding(.horizontal, Space.s)
        .frame(height: Metrics.row + Space.xs)
        .background(Palette.hover, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        .padding(.horizontal, Space.s)
    }

    private func sectionHeader(_ title: String, add: (() -> Void)?) -> some View {
        HStack {
            Text(title).captionText().foregroundStyle(Palette.textTertiary)
            Spacer()
            if let add {
                Button(action: add) { Image(systemName: "plus").foregroundStyle(Palette.textTertiary) }
                    .buttonStyle(.plain)
                    .help(String(localized: "Add a folder"))
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.top, Space.l)
        .padding(.bottom, Space.xs)
    }

    @ViewBuilder
    private func projectSection(_ group: SidebarModel.Group) -> some View {
        let open = !collapsed.contains(group.id) || !query.isEmpty
        Button {
            if collapsed.contains(group.id) { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
        } label: {
            SidebarRow(group.project.name, systemImage: open ? "folder" : "folder.fill") {
                if group.isRunning { Circle().fill(Palette.running).frame(width: Metrics.dot, height: Metrics.dot) }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(String(localized: "New Chat")) { workspace.startDraft(in: group.id) }
            Button(String(localized: "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([group.project.url]) }
            Divider()
            Button(String(localized: "Remove from xBot")) { workspace.removeProject(group.id) }
        }
        if open {
            ForEach(group.chats) { chatRow($0) }
            if group.hidden > 0 {
                Button { expanded.insert(group.id) } label: {
                    SidebarRow(String(localized: "Show all \(group.chats.count + group.hidden)"))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.leading, Space.l + Space.s)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func chatRow(_ chat: Chat, indent: Bool = true) -> some View {
        Group {
            if renaming == chat.id {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .bodyText()
                    .padding(.horizontal, Space.s)
                    .frame(height: Metrics.row)
                    .raisedSurface(radius: Radius.small)
                    .onSubmit { workspace.rename(chat.id, to: renameText); renaming = nil }
                    .onExitCommand { renaming = nil }
            } else {
                Button { workspace.open(chat.id) } label: {
                    SidebarRow(chat.title, isSelected: workspace.selectedChatID == chat.id) {
                        if workspace.isRunning(chat.id) { ProgressView().controlSize(.mini) }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(String(localized: "Rename")) { renameText = chat.title; renaming = chat.id }
                    Button(String(localized: "Delete Chat"), role: .destructive) { workspace.deleteChatWithUndo(chat.id) }
                }
            }
        }
        .padding(.leading, indent ? Space.l + Space.s : 0)
    }

    private var footer: some View {
        HStack(spacing: Space.m) {
            if workspace.availableHarnesses.isEmpty {
                if workspace.isDiscovering {
                    ProgressView().controlSize(.mini)
                    Text(String(localized: "Looking for agents…")).captionText().foregroundStyle(Palette.textTertiary)
                } else {
                    Text(String(localized: "No agent found")).captionText().foregroundStyle(Palette.textTertiary)
                    Button(String(localized: "Look again")) { Task { await workspace.refreshHarnesses() } }
                        .buttonStyle(.link)
                        .captionText()
                }
            } else {
                ForEach(workspace.availableHarnesses, id: \.self) { kind in
                    HStack(spacing: Space.xs) {
                        Circle().fill(Palette.agent(kind)).frame(width: Metrics.dot, height: Metrics.dot)
                        Text(kind.displayName).captionText().foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}
```

- [ ] **Step 4: `XBotApp.swift`** — `.windowStyle(.hiddenTitleBar)` on the `Window`; commands: replace `.newItem` with "New Chat" ⌘N → `workspace.startDraft(in: nil)` and "Close Tab" ⌘W; add `CommandGroup(after: .sidebar)`-free `SidebarCommands()`; add "Search" ⌘K → `workspace.requestSearchFocus()` (in `CommandGroup(after: .textEditing)`).

- [ ] **Step 5: Build, test, render** the sidebar with three projects (one running, one with 7 chats), Inbox and Recent, light and dark. Commit — `"The window and sidebar, rebuilt."`

---

### Task 5: Home and the composer

**Files:**
- Create: `apps/mac/Sources/XBotUI/Shell/HomeView.swift`, `apps/mac/Sources/XBotUI/Chat/Composer.swift`
- Delete: `apps/mac/Sources/XBotUI/Shell/EmptyState.swift`, `apps/mac/Sources/XBotUI/Chat/ChatComposer.swift`

**Interfaces — Consumes:** `Workspace.draft`, `draftHarness`, `sendDraft()`, `use(_:)`, `branch(for:)`, `composerFocusRequest`; chat setters. **Produces:** `HomeView(workspace:composer:addProject:)`, `Composer(workspace:target:namespace:addProject:)` with `Composer.Target { case draft, chat(UUID) }`.

- [ ] **Step 1: `Composer.swift`**

```swift
import SwiftUI
import XBotCore

/// The one composer: on Home it writes the draft; docked in a chat it sends to that chat.
/// A context strip (project, branch, agents) on top; the text; then the chips and send.
struct Composer: View {
    enum Target: Equatable { case draft, chat(UUID) }

    let workspace: Workspace
    let target: Target
    let namespace: Namespace.ID
    let addProject: () -> Void
    @State private var chatText = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            contextStrip
            VStack(alignment: .leading, spacing: Space.s) {
                TextField(placeholder, text: text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .readingText()
                    .lineLimit(1...10)
                    .focused($focused)
                    .onSubmit(send)
                HStack(spacing: Space.xxs) {
                    agentMenu
                    permissionMenu
                    planMenu
                    Spacer(minLength: Space.s)
                    if let reason = blockedReason {
                        Text(reason).captionText().foregroundStyle(Palette.textTertiary).lineLimit(1)
                    }
                    sendButton
                }
            }
            .padding(Space.m)
        }
        .background(Palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .strokeBorder(focused ? Palette.accent.opacity(0.4) : Palette.hairline)
        )
        .floatingShadow()
        .matchedGeometryEffect(id: "composer", in: namespace)
        .motion(Motion.quick, value: focused)
        .onAppear { focused = true }
        .onChange(of: workspace.composerFocusRequest) { focused = true }
    }

    // MARK: Pieces

    private var contextStrip: some View {
        HStack(spacing: Space.s) {
            Menu {
                Button(String(localized: "Inbox")) { workspace.draft.projectID = nil }
                ForEach(workspace.projects) { project in
                    Button(project.name) { workspace.draft.projectID = project.id }
                }
                Divider()
                Button(String(localized: "Add a folder…"), action: addProject)
            } label: {
                Label(projectName, systemImage: "folder").font(Typography.chip)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(target == .draft ? .visible : .hidden)
            .fixedSize()
            .disabled(target != .draft)
            if let branch = workspace.branch(for: projectID) {
                Label(branch, systemImage: "arrow.triangle.branch").font(Typography.mono).lineLimit(1)
            }
            Spacer()
            ForEach(workspace.availableHarnesses, id: \.self) { kind in
                Circle().fill(Palette.agent(kind)).frame(width: Metrics.dot, height: Metrics.dot).help(kind.displayName)
            }
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s - 2)
        .background(Palette.inset)
    }

    private var agentMenu: some View {
        Menu {
            ForEach(workspace.availableHarnesses, id: \.self) { kind in
                Section(kind.displayName) {
                    ForEach(kind.models, id: \.self) { model in
                        Button(model ?? String(localized: "Default model")) { choose(kind, model) }
                    }
                }
            }
        } label: {
            Chip(harness?.displayName ?? String(localized: "No agent"), detail: model.map { "· \($0)" },
                 dot: harness.map(Palette.agent), showsChevron: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isRunning)
    }

    private var permissionMenu: some View {
        Menu {
            ForEach(PermissionMode.allCases, id: \.self) { mode in
                Button { setMode(mode) } label: { Label(mode.title, systemImage: mode.symbol) }
            }
        } label: {
            Chip(mode.title, systemImage: mode.symbol, showsChevron: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var planMenu: some View {
        Menu {
            Toggle(String(localized: "Review plan first"), isOn: Binding(get: { reviewPlan }, set: setReview))
        } label: {
            Chip(String(localized: "Plan"), systemImage: "list.bullet.clipboard",
                 detail: planMode && !reviewPlan ? String(localized: "· runs at once") : nil, isOn: planMode)
        } primaryAction: {
            setPlan(!planMode)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Plan first: review the steps, then watch them run"))
    }

    private var sendButton: some View {
        let canSend = !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && blockedReason == nil
        return Button {
            if isRunning, case .chat(let id) = target { workspace.stop(id) } else { send() }
        } label: {
            Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                .font(Typography.emphasis.weight(.bold))
                .foregroundStyle(Palette.textInverse)
                .frame(width: Metrics.sendButton, height: Metrics.sendButton)
                .background(isRunning || canSend ? Palette.accent : Palette.textTertiary, in: Circle())
        }
        .buttonStyle(XBotButtonStyle())
        .disabled(!isRunning && !canSend)
        .keyboardShortcut(isRunning ? KeyboardShortcut(".", modifiers: .command) : KeyboardShortcut(.return, modifiers: []))
        .help(isRunning ? String(localized: "Stop (⌘.)") : String(localized: "Send"))
        .motion(Motion.quick, value: canSend)
    }

    // MARK: State, by target

    private var chat: Chat? {
        if case .chat(let id) = target { workspace.chat(id) } else { nil }
    }

    private var text: Binding<String> {
        target == .draft
            ? Binding(get: { workspace.draft.text }, set: { workspace.draft.text = $0 })
            : $chatText
    }

    private var projectID: UUID? { chat?.projectID ?? (target == .draft ? workspace.draft.projectID : nil) }

    private var projectName: String {
        workspace.projects.first { $0.id == projectID }?.name ?? String(localized: "Inbox")
    }

    private var harness: HarnessKind? { chat?.harness ?? workspace.draftHarness }
    private var model: String? { chat.map(\.model) ?? (workspace.draft.harness == harness ? workspace.draft.model : nil) }
    private var mode: PermissionMode { chat?.mode ?? workspace.draft.mode }
    private var planMode: Bool { chat?.planMode ?? workspace.draft.planMode }
    private var reviewPlan: Bool { chat?.reviewPlan ?? workspace.draft.reviewPlan }
    private var isRunning: Bool { chat.map { workspace.isRunning($0.id) } ?? false }

    private var blockedReason: String? {
        if let chat { return workspace.sendBlockedReason(chat.id) }
        return workspace.draftHarness == nil && !workspace.isDiscovering
            ? String(localized: "No agent found") : nil
    }

    private var placeholder: String {
        guard planMode else { return String(localized: "Describe a task, a bug to fix, an idea to try…") }
        return reviewPlan
            ? String(localized: "Describe the change. You'll review the plan first.")
            : String(localized: "Describe the change. The plan runs straight away.")
    }

    private func choose(_ kind: HarnessKind, _ model: String?) {
        if let chat {
            if chat.harness != kind { workspace.setHarness(kind, for: chat.id) }
            workspace.setModel(model, for: chat.id)
        } else {
            workspace.draft.harness = kind
            workspace.draft.model = model
        }
    }

    private func setMode(_ mode: PermissionMode) {
        if let chat { workspace.setMode(mode, for: chat.id) } else { workspace.draft.mode = mode }
    }

    private func setPlan(_ on: Bool) {
        if let chat { workspace.setPlanMode(on, for: chat.id) } else { workspace.draft.planMode = on }
    }

    private func setReview(_ on: Bool) {
        if let chat { workspace.setReviewPlan(on, for: chat.id) } else { workspace.draft.reviewPlan = on }
    }

    private func send() {
        switch target {
        case .draft:
            withAnimation(Motion.panel) { _ = workspace.sendDraft() }
        case .chat(let id):
            // Cleared only when the workspace took it: a refused send keeps what was typed.
            if workspace.send(chatText, in: id) { chatText = "" }
        }
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

Note: the send button's ⏎ shortcut duplicates `onSubmit`; keep `onSubmit` and give the button no ⏎ shortcut (only ⌘. while running) — `.keyboardShortcut` conditionally: apply `.keyboardShortcut(".", modifiers: .command)` only when running, via a small `if`.

- [ ] **Step 2: `HomeView.swift`**

```swift
import SwiftUI
import XBotCore

/// "What should we work on?" — the composer, and four ways in.
struct HomeView: View {
    let workspace: Workspace
    let composer: Namespace.ID
    let addProject: () -> Void

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer(minLength: Space.xl)
            if workspace.availableHarnesses.isEmpty && !workspace.isDiscovering {
                noAgent
            } else {
                Text(String(localized: "What should we work on?")).heroText().foregroundStyle(Palette.textPrimary)
                Composer(workspace: workspace, target: .draft, namespace: composer, addProject: addProject)
                    .frame(maxWidth: Metrics.composerWidth)
                HStack(spacing: Space.m) {
                    ForEach(Suggestion.allCases, id: \.self) { suggestion in
                        SuggestionCard(suggestion: suggestion) { workspace.use(suggestion) }
                    }
                }
                .frame(maxWidth: Metrics.composerWidth)
            }
            Spacer(minLength: Space.xl)
            Spacer(minLength: Space.xl)
        }
        .padding(.horizontal, Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noAgent: some View {
        VStack(spacing: Space.m) {
            AppMarkView(size: Space.xxl + Space.l)
            Text(String(localized: "xBot works through an agent you already have.")).titleText()
            Text(String(localized: "Install Claude Code or Codex and sign in, then come back. xBot will find it."))
                .bodyText()
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: Space.m) {
                Link(String(localized: "Get Claude Code"), destination: URL(string: "https://claude.com/product/claude-code")!)
                Link(String(localized: "Get Codex"), destination: URL(string: "https://developers.openai.com/codex")!)
            }
            .font(Typography.chip)
            .tint(Palette.accent)
            Button(String(localized: "Look again")) { Task { await workspace.refreshHarnesses() } }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}

private struct SuggestionCard: View {
    let suggestion: Suggestion
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s) {
                Image(systemName: suggestion.symbol).font(Typography.title).foregroundStyle(Palette.accent)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(suggestion.title).bodyText().foregroundStyle(Palette.textPrimary)
                    Text(suggestion.subtitle).bodyText().foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, minHeight: Metrics.suggestionHeight, alignment: .topLeading)
            .raisedSurface()
            .background(hovering ? Palette.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .cardShadow()
            .offset(y: hovering ? -1 : 0)
        }
        .buttonStyle(XBotButtonStyle())
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
    }
}
```

- [ ] **Step 3: Build, test, render** Home (with projects; with Plan on; no agent), light and dark. Commit — `"Home: what should we work on, and one composer for everything."`

---

### Task 6: The transcript and the plan cards

**Files:**
- Rewrite: `apps/mac/Sources/XBotUI/Chat/ChatView.swift`, `Chat/MessageView.swift`
- Create: `apps/mac/Sources/XBotUI/Chat/MarkdownText.swift`
- Modify: `Chat/Plan/PlanView.swift`, `PlanReviewCard.swift`, `TasksCard.swift`, `StepRow.swift`, `PlanStatusBar.swift`

**Interfaces — Consumes:** `ReplyLayout`, `workedFor`, `retryLast`, `MessageMarkdown` blocks, kit.

- [ ] **Step 1: `MarkdownText.swift`**

```swift
import SwiftUI
import XBotCore

/// A reply's text: prose, headings, lists and code, at reading size.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s + Space.xxs) {
            ForEach(MessageMarkdown.blocks(of: text)) { block in
                switch block {
                case .prose(let prose):
                    Text(Self.inline(prose)).readingText().textSelection(.enabled)
                case .heading(let title, let level):
                    Text(Self.inline(title))
                        .xbotFont(level == 1 ? Typography.title : Typography.emphasis, tracking: level == 1 ? -0.2 : 0)
                        .padding(.top, Space.xs)
                case .list(let items, let ordered):
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                                Text(verbatim: ordered ? "\(index + 1)." : "•")
                                    .readingText()
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.textTertiary)
                                    .frame(minWidth: Space.l, alignment: .trailing)
                                Text(Self.inline(item)).readingText().textSelection(.enabled)
                            }
                        }
                    }
                case .code(let code, let language):
                    CodeBlockView(code: code, language: language)
                }
            }
        }
        .foregroundStyle(Palette.textPrimary)
    }

    /// Inline markdown, with code spans drawn as small inset chips.
    static func inline(_ text: String) -> AttributedString {
        var attributed = MessageMarkdown.inline(text)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = Typography.mono
            attributed[run.range].backgroundColor = Palette.inset
        }
        return attributed
    }
}
```

- [ ] **Step 2: `MessageView.swift`** — two views:

```swift
import AppKit
import SwiftUI
import XBotCore

/// The person's message: right-aligned, on a raised fill, as typed.
struct UserMessage: View {
    let parts: [Part]

    var body: some View {
        Text(parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n"))
            .readingText()
            .textSelection(.enabled)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Space.m + 2)
            .padding(.vertical, Space.s + 1)
            .raisedSurface()
            .frame(maxWidth: Metrics.readingWidth * 0.8, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The agent's reply: "● Claude Code worked for 41s", then text, folded tools, notices, failures.
struct AgentReply: View {
    let harness: HarnessKind
    let parts: [Part]
    var workedFor: TimeInterval?
    var isLive = false
    var sentAt: Date?
    var retry: (() -> Void)?
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header
            ForEach(Array(ReplyLayout.segments(parts).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text): MarkdownText(text: text)
                case .tools(let tools): ToolFold(tools: tools, isLive: isLive)
                case .notice(let text): Text(text).captionText().foregroundStyle(Palette.textTertiary)
                case .failure(let reason): FailureCallout(reason: reason, retry: isLive ? nil : retry)
                }
            }
            if !isLive {
                actions.opacity(hovering ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
    }

    private var header: some View {
        HStack(spacing: Space.xs) {
            Circle().fill(Palette.agent(harness)).frame(width: Metrics.dot + 1, height: Metrics.dot + 1)
            if isLive {
                Text(String(localized: "\(harness.displayName) is working…"))
                ProgressView().controlSize(.mini)
            } else if let workedFor {
                Text(String(localized: "\(harness.displayName) worked for \(Elapsed.format(workedFor))"))
            } else {
                Text(harness.displayName)
            }
        }
        .captionText()
        .foregroundStyle(Palette.textTertiary)
    }

    private var actions: some View {
        HStack(spacing: Space.xs) {
            IconButton(copied ? "checkmark" : "doc.on.doc", help: String(localized: "Copy reply")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(plainText, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            }
            if let sentAt {
                Text(sentAt, format: .dateTime.hour().minute()).captionText().foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var plainText: String {
        parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n\n")
    }
}

/// A run of tools as one line — "Read 3 files, ran a command" — that opens to every tool.
private struct ToolFold: View {
    let tools: [ToolPart]
    let isLive: Bool
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button { open.toggle() } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "square.stack.3d.up").foregroundStyle(Palette.textTertiary)
                    Text(ToolLabel.summary(of: tools)).captionText().foregroundStyle(Palette.textSecondary)
                    Image(systemName: open ? "chevron.up" : "chevron.down").imageScale(.small)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .buttonStyle(.plain)
            if open {
                ForEach(tools, id: \.id) { ToolLine(tool: $0) }.padding(.leading, Metrics.stepIndent)
            } else if isLive, let running = tools.last(where: { $0.output == nil }) {
                ToolLine(tool: running).padding(.leading, Metrics.stepIndent)
            }
        }
        .motion(Motion.quick, value: open)
    }
}

private struct FailureCallout: View {
    let reason: String
    let retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.failure)
            Text(reason).bodyText().foregroundStyle(Palette.textPrimary).textSelection(.enabled)
            Spacer(minLength: Space.s)
            if let retry {
                Button(String(localized: "Retry"), action: retry).buttonStyle(QuietButtonStyle())
            }
        }
        .padding(Space.m)
        .background(Palette.failureTint, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }
}
```

- [ ] **Step 3: `ChatView.swift`**

```swift
import SwiftUI
import XBotCore

struct ChatView: View {
    let workspace: Workspace
    let chat: Chat
    let composer: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xl) {
                    ForEach(workspace.messages(in: chat.id)) { message in
                        if let plan = message.plan {
                            PlanView(workspace: workspace, chatID: chat.id, messageID: message.id, plan: plan)
                        } else if message.role == .user {
                            UserMessage(parts: message.parts)
                        } else {
                            AgentReply(harness: chat.harness, parts: message.parts,
                                       workedFor: workspace.workedFor(message.id, in: chat.id),
                                       sentAt: message.createdAt,
                                       retry: { workspace.retryLast(in: chat.id) })
                        }
                    }
                    if let live = workspace.live[chat.id] {
                        AgentReply(harness: chat.harness, parts: live, isLive: true)
                    }
                }
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.xl)
                .frame(maxWidth: Metrics.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            PlanStatusBar(workspace: workspace, chatID: chat.id)
            Composer(workspace: workspace, target: .chat(chat.id), namespace: composer, addProject: {})
                .frame(maxWidth: Metrics.readingWidth)
                .padding(.horizontal, Space.xl)
                .padding(.bottom, Space.l)
                .padding(.top, Space.s)
        }
    }
}
```

- [ ] **Step 4: Plan cards on the kit.**
  - `PlanView`'s planning state: `Card(title: "Planning", meta: "READ-ONLY") { InsetPanel { ProgressView + tool lines } }`.
  - `PlanReviewCard`: keep the intro line above; the card is `Card(title: "Review the plan", subtitle: nil, meta: "\(n) STEPS") { caption; InsetPanel { rows; Add step } } footer: { CardFooter("READ-ONLY PLANNING") { Cancel (QuietButtonStyle); Run plan ⌘↩ (PrimaryButtonStyle) } }`.
  - `TasksCard`: intro line above; `Card(title: "Tasks", meta: counts.uppercased()) { progress hairline; note; InsetPanel { rows } } footer: { CardFooter(status) { EmptyView() } }` where status is "RUNNING · 26S", "FINISHED · 1 FAILED", "STOPPED"; "Plan updated · N added" moves into the footer status ("FINISHED · 2 ADDED").
  - `StepRow`: added steps show `StatusPill(.accent, "ADDED")` after the title while the plan runs; failed note stays red caption.
  - `PlanStatusBar`: `StatusPill` (`.success` "FINISHED", `.failure` "STOPPED · 1 FAILED") + Resume (`QuietButtonStyle`).

- [ ] **Step 5: Build, test, render** a chat with a markdown reply (heading, list, inline code, code block), a folded tool run, a failure with Retry, a live reply, the review card and the running Tasks card, light and dark. Commit — `"A calmer transcript, and plan cards on the kit."`

---

### Task 7: Docs, install, review

- [ ] **Step 1:** `CLAUDE.md` invariant 6 → "Deleting a bot (its computer and browser profile) is confirmed once. Deleting a chat is immediate and undoable from the toast." `CHANGELOG.md` Unreleased: the redesign. `docs/08-design-system.md`: a banner pointing at the premium-UI spec and `Palette.swift`/`Typography.swift` as the source of truth for colour and type.
- [ ] **Step 2:** Full suite ten times for the core suites; build release; install to `/Applications` (previous build to the Trash); launch; check the library still opens.
- [ ] **Step 3: Commit** — `"Docs for the redesign."`
