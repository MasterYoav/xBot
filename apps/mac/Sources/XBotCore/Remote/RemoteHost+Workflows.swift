import Foundation
import XBotBrain
import XBotRemote

/// Jev workflows from a phone: the list, with Run now (and Run with…), through the same
/// `Workspace` methods as the Mac's Workflows page. Only while the Mac has Jev Workflows on.
extension RemoteHost {
    func answerWorkflows(_ message: ClientMessage) -> (UUID?, HostMessage?) {
        switch message {
        case .listWorkflows(let request):
            return (request, workflowsAnswer(request))

        case .runWorkflow(let request, let id, let input):
            guard let workflow = workspace.workflow(id) else {
                return (request, .reply(requestID: request, ok: false, reason: String(localized: "That workflow isn't on the Mac any more."), chatID: nil))
            }
            if let why = workspace.workflowBlockedReason(workflow) {
                return (request, .reply(requestID: request, ok: false, reason: why, chatID: nil))
            }
            guard let run = workspace.runWorkflow(id, input: input ?? "") else {
                return (request, .reply(requestID: request, ok: false, reason: String(localized: "It couldn't start just now."), chatID: nil))
            }
            return (request, .reply(requestID: request, ok: true, reason: nil, chatID: run.id))

        default:
            return answerCrew(message)
        }
    }

    private func workflowsAnswer(_ request: UUID) -> HostMessage {
        guard workspace.showsWorkflows else { return .workflows(requestID: request, workflows: [], available: false) }
        return .workflows(requestID: request, workflows: workspace.workflows.map(remote), available: true)
    }

    private func remote(_ workflow: Workflow) -> RemoteWorkflow {
        let schedule: RemoteSchedule? = if case .schedule(let s) = workflow.trigger { Self.remote(s) } else { nil }
        let runs = workspace.runs(ofWorkflow: workflow.id).prefix(10).map {
            RemoteRun(id: $0.id, startedAt: $0.createdAt, isRunning: workspace.isRunning($0.id),
                      failed: !workspace.isRunning($0.id) && workspace.runFailed($0.id))
        }
        let blocked = workspace.isRunning(workflow: workflow.id) ? nil : workspace.workflowBlockedReason(workflow)
        return RemoteWorkflow(
            id: workflow.id, name: workflow.name, schedule: schedule, stepTitles: workflow.steps.map(\.title),
            isEnabled: workflow.isEnabled, nextRun: workflow.isEnabled ? workflow.nextRun() : nil,
            lastRunAt: workflow.lastRunAt, runs: Array(runs), blocked: blocked)
    }
}
