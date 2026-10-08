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
