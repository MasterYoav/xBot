import Foundation
import XBotBrain

/// "Let Jev choose", in the composer's agent menu: before each message runs, Jev picks the CLI,
/// model and effort from the message itself (one call; see `JevPick`). Only while Jev Workflows
/// is on; if Jev can't be reached the chat's own agent answers, and the reply says why.
extension Workspace {
    public func setJevChooses(_ on: Bool, for id: UUID) { update(id) { $0.jevChooses = on } }

    /// Whether the chat's next message asks Jev first.
    public func jevChoosesActive(_ id: UUID) -> Bool {
        jev.workflowsEnabled && chat(id)?.jevChooses == true
    }

    func sendChoosingWithJev(_ turnPrompt: String, asked: String, in id: UUID) {
        guard let current = chat(id) else { return }
        let fallback = BrainChoice(harness: current.harness, model: current.model, effort: current.effort)
        live[id] = []
        launch(id) { w, token in
            let picked = await w.pickBrain(for: asked, fallback: fallback)
            guard w.turns[id]?.token == token else { return }
            w.update(id) { chat in
                // A session belongs to its CLI: another CLI starts its own.
                if chat.harness != picked.choice.harness { chat.sessionID = nil }
                chat.harness = picked.choice.harness
                chat.model = picked.choice.model
                chat.effort = picked.choice.effort
            }
            w.live[id] = [.notice(picked.notice)]
            guard let chat = w.chat(id), let brain = w.brains[chat.harness] else {
                w.live[id, default: []].append(.failure(String(localized: "No agent is installed on this Mac.")))
                return
            }
            let request = TurnRequest(
                prompt: turnPrompt, directory: w.directory(for: chat), model: w.turnModel(for: chat),
                mode: chat.mode, resumeID: chat.sessionID, effort: chat.effort, instructions: w.instructions(for: chat)
            )
            for await event in w.events(brain, request, harness: chat.harness) {
                w.receive(event, in: id, turn: token)
            }
        }
    }
}
