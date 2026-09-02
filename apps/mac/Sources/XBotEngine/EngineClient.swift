import Foundation

/// Everything the app asks of the engine.
///
/// A protocol with two implementations from the start, not one extracted later: `StubEngineClient`
/// here, and the real REST/SSE client. docs/05-mac-app.md calls the stub a first-class deliverable
/// and it is — it is how the UI is built while the engine is somewhere else, how snapshot tests stay
/// deterministic, and how someone with no container runtime can still run the app.
public protocol EngineClient: Sendable {
    func agents() async throws -> [Agent]
    func channels() async throws -> [Channel]
    func messages(in channel: Channel.ID) async throws -> [Message]

    /// Send, and stream the turn back.
    ///
    /// The stream is the heart of the app. It must be incremental, must survive a truncated
    /// response, and must be orderable per turn while several turns run at once — so it is one
    /// stream per send rather than one shared event bus the caller has to filter.
    func send(
        _ text: String,
        to channel: Channel.ID
    ) -> AsyncThrowingStream<TurnEvent, Error>
}

public enum EngineError: Error, Sendable {
    case notRunning
    case unknownChannel(Channel.ID)
}
