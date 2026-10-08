import Foundation

/// With a schema, Codex's answer is its last message, as JSON text. Each message is held back until
/// anything else happens — another message, a tool — which proves it was not the last; whatever is
/// held when the turn ends is the answer. If the turn fails, the held message was ordinary text.
struct SchemaTail {
    private var held: String?

    mutating func process(_ event: BrainEvent) -> [BrainEvent] {
        switch event {
        case .text(let text):
            defer { held = text }
            return held.map { [.text($0)] } ?? []
        case .done:
            defer { held = nil }
            return (held.map { [.structured($0)] } ?? []) + [.done]
        case .failed:
            defer { held = nil }
            return (held.map { [.text($0)] } ?? []) + [event]
        default:
            defer { held = nil }
            return (held.map { [.text($0)] } ?? []) + [event]
        }
    }
}
