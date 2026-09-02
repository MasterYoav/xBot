import Foundation

/// What `AppState` holds before a real engine is reachable.
///
/// Not an optional `EngineClient?` everywhere it is used: a client that answers "not running" to
/// every call keeps every call site's existing error handling — `try? await engine.agents() ?? []`
/// and friends — working unchanged whether the caller is talking to the stub, the void, or a real
/// engine that just went away. The alternative, threading an optional through `AppState`, would
/// turn every one of those call sites into an `if let` that says nothing `.notRunning` doesn't.
public struct UnavailableEngineClient: EngineClient {
    public init() {}

    public func agents() async throws -> [Agent] { throw EngineError.notRunning }
    public func channels() async throws -> [Channel] { throw EngineError.notRunning }
    public func createAgent(_ draft: AgentDraft) async throws -> Agent { throw EngineError.notRunning }
    public func createChannel(agentIds: [Agent.ID]) async throws -> Channel {
        throw EngineError.notRunning
    }
    public func messages(in channel: Channel.ID) async throws -> [Message] {
        throw EngineError.notRunning
    }
    public func activity(for agent: Agent.ID) async throws -> [ActivityEntry] {
        throw EngineError.notRunning
    }
    public func updateAgent(_ id: Agent.ID, _ patch: AgentPatch) async throws -> Agent {
        throw EngineError.notRunning
    }
    public func availableModels() async throws -> [ModelSelection] { throw EngineError.notRunning }
    public func setControl(_ control: ScreenControl, for agent: Agent.ID) async throws {
        throw EngineError.notRunning
    }

    public func send(
        _ text: String,
        to channel: Channel.ID
    ) -> AsyncThrowingStream<TurnEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: EngineError.notRunning) }
    }

    public func screen(for agent: Agent.ID, cadence: ScreenCadence) -> AsyncStream<ScreenFrame> {
        // Finishes rather than hangs, for the same reason the stub's stopped-cadence stream does:
        // a view awaiting frames that will never come must not be left suspended forever.
        AsyncStream { $0.finish() }
    }
}
