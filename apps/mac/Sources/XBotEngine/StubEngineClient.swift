import Foundation

/// The engine, faked, well enough to build the whole conversation against.
///
/// An actor because it holds mutable conversation state and the UI hits it from several tasks —
/// the same reason the real client is one. Fixtures deliberately include the awkward cases the
/// happy path hides: a long agent name that has to truncate in the rail, a message that streams in
/// pieces rather than arriving whole, and a turn that fails so the retry state is reachable
/// without unplugging anything.
public actor StubEngineClient: EngineClient {
    private var messagesByChannel: [Channel.ID: [Message]]
    private let fixedAgents: [Agent]
    private let fixedChannels: [Channel]

    /// How long a stubbed token takes to arrive.
    ///
    /// Not zero. A stub that answers instantly hides every scroll-pinning and streaming-layout bug
    /// the real stream will find, which defeats the point of building against it.
    private let tokenDelay: Duration

    public init(tokenDelay: Duration = .milliseconds(28)) {
        self.tokenDelay = tokenDelay

        let agents = [
            Agent(
                id: "orchestrator",
                name: "Orchestrator",
                label: "Orchestrate and use the other agents",
                avatarSeed: "orchestrator",
                model: ModelSelection(
                    provider: "Anthropic",
                    model: "Claude Sonnet 4.5",
                    capabilities: ["vision", "tools"]
                )
            ),
            Agent(
                id: "inbox",
                name: "Inbox",
                label: "Reads and drafts your mail",
                avatarSeed: "inbox",
                model: ModelSelection(
                    provider: "OpenAI",
                    model: "gpt-4.1",
                    capabilities: ["vision", "tools"]
                )
            ),
            Agent(
                id: "researcher",
                name: "Researcher with a long name",
                label: "Reads the web and writes it up",
                avatarSeed: "researcher",
                model: ModelSelection(provider: "Ollama", model: "llama3.1", capabilities: ["tools"])
            ),
        ]
        fixedAgents = agents
        fixedChannels = agents.map { Channel(id: "channel-\($0.id)", agentIds: [$0.id]) }

        messagesByChannel = [
            "channel-orchestrator": [
                Message(
                    id: "m1",
                    author: .user,
                    text: "Check whether the Lisbon flight is still refundable.",
                    sentAt: Date(timeIntervalSinceNow: -420)
                ),
                Message(
                    id: "m2",
                    author: .agent("orchestrator"),
                    text: """
                        It is, until Thursday. After that the fare drops to a 40% refund. \
                        I've left the booking open in the browser if you want to look.
                        """,
                    sentAt: Date(timeIntervalSinceNow: -400)
                ),
                Message(
                    id: "m3",
                    author: .user,
                    text: "Leave it for now, thanks.",
                    sentAt: Date(timeIntervalSinceNow: -380)
                ),
            ],
            "channel-inbox": [],
            "channel-researcher": [],
        ]
    }

    public func agents() async throws -> [Agent] { fixedAgents }
    public func channels() async throws -> [Channel] { fixedChannels }

    public func messages(in channel: Channel.ID) async throws -> [Message] {
        guard let found = messagesByChannel[channel] else {
            throw EngineError.unknownChannel(channel)
        }
        return found
    }

    public nonisolated func send(
        _ text: String,
        to channel: Channel.ID
    ) -> AsyncThrowingStream<TurnEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return }
                await self.stream(text, to: channel, into: continuation)
            }
            // Cancelling the stream must stop the work behind it. Without this a user who switches
            // agents mid-turn leaves a task appending to a conversation nobody is looking at.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func stream(
        _ text: String,
        to channel: Channel.ID,
        into continuation: AsyncThrowingStream<TurnEvent, Error>.Continuation
    ) async {
        let id = "reply-\(UUID().uuidString)"
        messagesByChannel[channel, default: []].append(
            Message(id: "sent-\(UUID().uuidString)", author: .user, text: text, state: .complete)
        )
        continuation.yield(.started(messageId: id))

        // One fixture that fails, reachable on demand rather than by luck: the retry state needs to
        // be buildable without waiting for a real network to misbehave.
        if text.lowercased().hasPrefix("fail") {
            continuation.yield(.failed(messageId: id, reason: "The model didn't respond"))
            continuation.finish()
            return
        }

        if text.lowercased().contains("browse") || text.lowercased().contains("check") {
            continuation.yield(.toolCall(messageId: id, name: "browser.navigate", target: "flights"))
        }

        let reply = Self.reply(to: text)
        var pending = ""
        for word in reply.split(separator: " ", omittingEmptySubsequences: false) {
            if Task.isCancelled {
                continuation.finish()
                return
            }
            pending += (pending.isEmpty ? "" : " ") + word
            continuation.yield(.textDelta(messageId: id, text: pending.isEmpty ? "" : " " + word))
            try? await Task.sleep(for: tokenDelay)
        }

        messagesByChannel[channel, default: []].append(
            Message(id: id, author: .agent("orchestrator"), text: reply, state: .complete)
        )
        continuation.yield(.finished(messageId: id))
        continuation.finish()
    }

    private static func reply(to text: String) -> String {
        """
        I had a look. Nothing here is real yet — this is the stub engine, which exists so the \
        conversation can be built and tested before it is connected to anything. You typed \
        "\(text.prefix(60))".
        """
    }
}
