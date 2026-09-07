import Foundation
import Observation
import XBotEngine

/// The Routines panel: what this agent has standing, and whether it stays standing.
///
/// Show and stop, never compose. The engine has no create and no edit endpoint on purpose —
/// `server/src/routines/routes.ts` says making one is conversational, because the hard part is
/// turning a sentence into a schedule and a channel and that is what a conversation is for. So the
/// panel's answer to "how do I make one" is a sentence telling the person to ask the agent, which
/// is also the only answer that does not need a cron field in a settings pane.
@MainActor
@Observable
public final class RoutinesState {
    public private(set) var routines: [Routine] = []
    public private(set) var isLoading = false
    public private(set) var problem: String?

    public init() {}

    public func load(for agent: Agent.ID?, fetch: () async throws -> [Routine]) async {
        isLoading = true
        problem = nil
        defer { isLoading = false }
        do {
            let all = try await fetch()
            // Filtered here rather than asked for: the engine's list route is owner-scoped and takes
            // no agent, and inventing a query parameter it does not have would 200 with everything
            // and look like it worked.
            routines = agent.map { id in all.filter { $0.agentId == id } } ?? all
        } catch {
            // Never an empty list on failure. "This agent has no routines" and "I could not ask" are
            // opposite answers, and only one of them means the person should go and make one.
            routines = []
            problem = String(
                localized: "Routines couldn't be read. They need the engine to be running."
            )
        }
    }

    /// Flip a routine and put it back if the engine refuses.
    ///
    /// Optimistic because a switch that waits for a round trip feels broken, and reverted on failure
    /// because a switch that lies about a routine still firing at 09:00 is worse than a slow one.
    public func setEnabled(
        _ id: String,
        to enabled: Bool,
        write: (String, Bool) async throws -> Void
    ) async {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        let previous = routines[index]
        routines[index] = previous.settingEnabled(enabled)
        do {
            try await write(id, enabled)
        } catch {
            routines[index] = previous
            problem = String(localized: "That routine couldn't be changed. Is the engine running?")
        }
    }

    public func delete(_ id: String, write: (String) async throws -> Void) async {
        let previous = routines
        routines.removeAll { $0.id == id }
        do {
            try await write(id)
        } catch {
            routines = previous
            problem = String(localized: "That routine couldn't be deleted. Is the engine running?")
        }
    }
}

extension Routine {
    /// The same routine with its switch moved. `Routine` is a `let`-only value, so this is how the
    /// optimistic flip is expressed without making every field mutable for one caller.
    func settingEnabled(_ enabled: Bool) -> Routine {
        Routine(
            id: id,
            agentId: agentId,
            schedule: schedule,
            timezone: timezone,
            instruction: instruction,
            channelName: channelName,
            channelIsGone: channelIsGone,
            enabled: enabled,
            nextRunAt: nextRunAt,
            lastRunStatus: lastRunStatus,
            lastRunAt: lastRunAt
        )
    }
}
