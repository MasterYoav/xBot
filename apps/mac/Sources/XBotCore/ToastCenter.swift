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
        guard let action = current?.action else { return }
        dismiss()
        action.run()
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
