import Foundation
import Observation

/// `xbot_ask`: an agent's question waiting, per chat, for the person's next message in that chat
/// (from the Mac's composer or the phone). The reply answers the question instead of starting a
/// turn, since the agent's turn is still running, waiting on it.
@MainActor
@Observable
public final class QuestionCenter {
    /// Chats with a question waiting.
    public private(set) var waiting: Set<UUID> = []
    @ObservationIgnored private var continuations: [UUID: CheckedContinuation<String?, Never>] = [:]
    @ObservationIgnored private var generation: [UUID: UUID] = [:]

    public init() {}

    public func isWaiting(in chatID: UUID) -> Bool { waiting.contains(chatID) }

    /// The person's reply, or nil when none came in time (or the turn stopped). A second question
    /// in the same chat ends the first unanswered.
    public func ask(in chatID: UUID, timeout: Duration) async -> String? {
        settle(chatID, with: nil)
        let id = UUID()
        generation[chatID] = id
        waiting.insert(chatID)
        let expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, self?.generation[chatID] == id else { return }
            self?.settle(chatID, with: nil)
        }
        let answer = await withCheckedContinuation { continuation in
            if generation[chatID] == id, waiting.contains(chatID) {
                continuations[chatID] = continuation
            } else {
                continuation.resume(returning: nil)
            }
        }
        expiry.cancel()
        return answer
    }

    /// Hands `text` to the question waiting in `chatID`. False when there's none.
    @discardableResult
    public func answer(_ text: String, in chatID: UUID) -> Bool {
        guard waiting.contains(chatID) else { return false }
        settle(chatID, with: text)
        return true
    }

    /// Ends a waiting question unanswered (the turn was stopped).
    public func cancel(in chatID: UUID) { settle(chatID, with: nil) }

    private func settle(_ chatID: UUID, with text: String?) {
        guard waiting.remove(chatID) != nil else { return }
        generation[chatID] = nil
        continuations.removeValue(forKey: chatID)?.resume(returning: text)
    }
}
