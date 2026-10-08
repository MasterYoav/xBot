import Foundation

// MARK: Usage

extension Workspace {
    /// A brain's events, with the usage it reports taken out and kept.
    func events(_ brain: any Brain, _ request: TurnRequest, harness: HarnessKind) -> AsyncStream<BrainEvent> {
        let source = brain.run(request)
        return AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                for await event in source {
                    if case .limits(let limits) = event {
                        self?.record(limits, for: harness)
                    } else {
                        continuation.yield(event)
                    }
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

    /// Claude Code's plan, from its account summary.
    public var claudePlan: String? { ClaudeAccount.plan() }
}

// MARK: Git

extension Workspace {
    public var gitInstalled: Bool { gitTool != nil }

    /// The project's git, made once and kept. Nil when git is not installed.
    public func git(for project: Project) -> ProjectGit? {
        guard let gitTool else { return nil }
        if let model = gitModels[project.id] { return model }
        let model = ProjectGit(directory: project.url, tool: gitTool)
        gitModels[project.id] = model
        return model
    }
}

// MARK: Pages

public enum Page: Equatable, Sendable {
    case main, profile
    case diff(projectID: UUID, file: GitFile)
}

extension Workspace {
    public func showDiff(_ file: GitFile, in project: Project) { page = .diff(projectID: project.id, file: file) }

    public static var mergeRequest: String {
        String(localized: "Pull the latest changes from the remote and merge them with mine. Resolve any conflicts, run the tests, then tell me what you did.")
    }

    /// "Ask the agent to merge": sent to the open chat, or put in Home's composer.
    public func askToMerge() {
        if let id = selectedChatID, send(Self.mergeRequest, in: id) { return }
        draft.text = Self.mergeRequest
        composerFocusRequest += 1
    }
}

// MARK: Mentions

extension Workspace {
    /// Puts "@path" into the composer on screen: Home's, or the open chat's.
    public func mention(_ url: URL) {
        guard let project = contextProject else { return }
        pendingMention = FileTree.mention(url, in: project.url)
        mentionRequest += 1
    }
}

// MARK: History

extension Workspace {
    /// One pass of the indexer, then the profile's numbers read again.
    public func indexHistory() async {
        guard let indexer else { return }
        await indexer.index()
        history = await indexer.summary()
        planRunCount = attempt { try store.planRuns() } ?? 0
    }
}

// MARK: Defaults

extension Workspace {
    /// The agent a new chat starts with; nil means the one used most recently.
    public var defaultHarness: HarnessKind? {
        get { defaults.string(forKey: "default.harness").flatMap(HarnessKind.init(rawValue:)) }
        set {
            defaults.set(newValue?.rawValue, forKey: "default.harness")
            draft.harness = newValue
            draft.model = nil
        }
    }

    /// The reasoning a new chat starts with; nil means the agent's own default.
    public var defaultEffort: Effort? {
        get { defaults.string(forKey: "default.effort").flatMap(Effort.init(rawValue:)) }
        set {
            defaults.set(newValue?.rawValue, forKey: "default.effort")
            draft.effort = newValue
        }
    }

    public var defaultMode: PermissionMode {
        get { defaults.string(forKey: "default.mode").flatMap(PermissionMode.init(rawValue:)) ?? .editFiles }
        set {
            defaults.set(newValue.rawValue, forKey: "default.mode")
            draft.mode = newValue
        }
    }

    func applyDraftDefaults() {
        draft.harness = defaultHarness
        draft.model = nil
        draft.effort = defaultEffort
        draft.mode = defaultMode
    }

    /// Where an installed agent's CLI is.
    public func executable(for kind: HarnessKind) -> URL? { (brains[kind] as? HarnessBrain)?.executable }
}
