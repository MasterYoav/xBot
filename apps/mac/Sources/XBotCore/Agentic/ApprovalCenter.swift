import Foundation
import Observation

/// Agentic Mode's guardrails: a risky action waits here for the person's yes or no, answered on
/// the phone (an approval card) or on the Mac, or it expires. See the Agentic Mode spec.
///
/// The center keeps no chats itself: `post` puts the card in the conversation and `update`
/// rewrites it with its answer (the workspace wires both to the chat's messages).
@MainActor
@Observable
public final class ApprovalCenter {
    public struct Pending: Equatable, Sendable {
        public var approval: ApprovalPart
        public var chatID: UUID
    }

    /// Waiting for an answer, oldest first.
    public private(set) var pending: [Pending] = []

    @ObservationIgnored public var post: (ApprovalPart, UUID) -> Void = { _, _ in }
    @ObservationIgnored public var update: (ApprovalPart, UUID) -> Void = { _, _ in }
    @ObservationIgnored private var waiting: [UUID: CheckedContinuation<ApprovalPart.State, Never>] = [:]

    /// How long an approval waits before it counts as Don't allow.
    public static let lifetime: Duration = .seconds(600)

    public init() {}

    /// Asks, and waits for the answer: `.allowed`, `.refused` or `.expired`.
    public func ask(_ approval: ApprovalPart, in chatID: UUID, timeout: Duration = ApprovalCenter.lifetime) async -> ApprovalPart.State {
        var approval = approval
        approval.state = .pending
        pending.append(Pending(approval: approval, chatID: chatID))
        post(approval, chatID)
        let id = approval.id
        let expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.settle(id, state: .expired, by: nil)
        }
        let state = await withCheckedContinuation { continuation in
            if pending.contains(where: { $0.approval.id == id }) {
                waiting[id] = continuation
            } else {
                // Answered before the wait began.
                continuation.resume(returning: answered[id] ?? .expired)
            }
        }
        expiry.cancel()
        answered[id] = nil
        return state
    }

    /// The person's answer. False when there's nothing waiting with that id (already answered).
    @discardableResult
    public func answer(_ id: UUID, allow: Bool, by device: String) -> Bool {
        settle(id, state: allow ? .allowed : .refused, by: device)
    }

    @ObservationIgnored private var answered: [UUID: ApprovalPart.State] = [:]

    @discardableResult
    private func settle(_ id: UUID, state: ApprovalPart.State, by device: String?) -> Bool {
        guard let index = pending.firstIndex(where: { $0.approval.id == id }) else { return false }
        var item = pending.remove(at: index)
        item.approval.state = state
        item.approval.answeredBy = device
        update(item.approval, item.chatID)
        if let continuation = waiting.removeValue(forKey: id) {
            continuation.resume(returning: state)
        } else {
            answered[id] = state
        }
        return true
    }
}
