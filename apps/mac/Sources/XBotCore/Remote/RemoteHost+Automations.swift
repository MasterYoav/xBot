import Foundation
import XBotBrain
import XBotRemote

/// Automations from a phone: the same list, editor and Run now as the Mac's Automations page.
extension RemoteHost {
    func answerAutomations(_ message: ClientMessage) -> (UUID?, HostMessage?) {
        switch message {
        case .listAutomations(let request):
            return (request, automationsAnswer(request))

        case .saveAutomation(let request, let remote):
            guard let agent = HarnessKind(rawValue: remote.agent) else {
                return (request, .reply(requestID: request, ok: false, reason: String(localized: "That agent isn't known on the Mac."), chatID: nil))
            }
            var steps: [AutomationStep] = []
            for step in remote.steps {
                guard let app = AutomationApp(storageKey: step.app) else {
                    return (request, .reply(requestID: request, ok: false, reason: String(localized: "A step uses an app the Mac doesn't know."), chatID: nil))
                }
                steps.append(AutomationStep(id: step.id, app: app, text: step.text))
            }
            if let projectID = remote.projectID, !workspace.projects.contains(where: { $0.id == projectID }) {
                return (request, .reply(requestID: request, ok: false, reason: String(localized: "That project isn't on the Mac any more."), chatID: nil))
            }
            let existing = workspace.automation(remote.id)
            var automation = existing ?? workspace.newAutomation()
            automation.id = remote.id
            automation.name = remote.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "New automation") : remote.name
            automation.trigger = remote.schedule.map { .schedule(Self.schedule($0)) } ?? .manual
            automation.steps = steps
            automation.harness = agent
            automation.model = remote.model
            automation.effort = remote.effort.flatMap(Effort.init(rawValue:))
            automation.projectID = remote.projectID
            automation.isEnabled = remote.isEnabled
            workspace.saveAutomation(automation)
            return (request, automationsAnswer(request))

        case .deleteAutomation(let request, let id):
            workspace.deleteAutomation(id)
            return (request, automationsAnswer(request))

        case .runAutomation(let request, let id):
            guard let automation = workspace.automation(id) else {
                return (request, .reply(requestID: request, ok: false, reason: String(localized: "That automation isn't on the Mac any more."), chatID: nil))
            }
            let why: String? = if workspace.isRunning(automation: id) {
                String(localized: "It's running already.")
            } else if !automation.hasWork {
                String(localized: "It has no steps to do yet.")
            } else if !workspace.availableHarnesses.contains(automation.harness) {
                String(localized: "\(automation.harness.displayName) isn't installed on the Mac.")
            } else { nil }
            if let why { return (request, .reply(requestID: request, ok: false, reason: why, chatID: nil)) }
            guard let run = workspace.runAutomation(id) else {
                return (request, .reply(requestID: request, ok: false, reason: String(localized: "It couldn't start just now."), chatID: nil))
            }
            return (request, .reply(requestID: request, ok: true, reason: nil, chatID: run.id))

        case .setAutomationHelper(let request, let on):
            do {
                if on { try AutomationHelper.install() } else { try AutomationHelper.uninstall() }
            } catch {
                return (request, .reply(requestID: request, ok: false, reason: error.localizedDescription, chatID: nil))
            }
            return (request, automationsAnswer(request))

        default:
            return answerCrew(message)
        }
    }

    private func automationsAnswer(_ request: UUID) -> HostMessage {
        .automations(requestID: request, automations: workspace.automations.map(remote), apps: paletteApps(),
                     runsWhileClosed: AutomationHelper.isInstalled)
    }

    private func remote(_ automation: Automation) -> RemoteAutomation {
        let schedule: RemoteSchedule? = if case .schedule(let s) = automation.trigger { Self.remote(s) } else { nil }
        let runs = workspace.runs(of: automation.id).prefix(10).map {
            RemoteRun(id: $0.id, startedAt: $0.createdAt, isRunning: workspace.isRunning($0.id),
                      failed: !workspace.isRunning($0.id) && workspace.runFailed($0.id))
        }
        return RemoteAutomation(
            id: automation.id, name: automation.name, schedule: schedule,
            steps: automation.steps.map { RemoteStep(id: $0.id, app: $0.app.storageKey, text: $0.text) },
            agent: automation.harness.rawValue, model: automation.model, effort: automation.effort?.rawValue,
            projectID: automation.projectID, isEnabled: automation.isEnabled,
            nextRun: automation.isEnabled ? automation.nextRun() : nil, lastRunAt: automation.lastRunAt, runs: Array(runs))
    }

    /// The Mac's palette: its apps, then the connectors and MCP servers it knows.
    private func paletteApps() -> [RemoteApp] {
        var apps = AutomationApp.builtIn.map { RemoteApp(key: $0.storageKey, title: $0.title) }
        var seen = Set<String>()
        for item in (workspace.abilities.items[.connectors] ?? []) + (workspace.abilities.items[.mcps] ?? [])
        where seen.insert(item.title.lowercased()).inserted {
            let app = AutomationApp.connector(item.title)
            apps.append(RemoteApp(key: app.storageKey, title: item.title, isConnector: true))
        }
        return apps
    }

    static func schedule(_ remote: RemoteSchedule) -> AutomationSchedule {
        switch remote {
        case .hourly(let m): .hourly(minute: m)
        case .daily(let h, let m): .daily(hour: h, minute: m)
        case .weekdays(let h, let m): .weekdays(hour: h, minute: m)
        case .weekly(let d, let h, let m): .weekly(weekday: d, hour: h, minute: m)
        }
    }

    static func remote(_ schedule: AutomationSchedule) -> RemoteSchedule {
        switch schedule {
        case .hourly(let m): .hourly(minute: m)
        case .daily(let h, let m): .daily(hour: h, minute: m)
        case .weekdays(let h, let m): .weekdays(hour: h, minute: m)
        case .weekly(let d, let h, let m): .weekly(weekday: d, hour: h, minute: m)
        }
    }
}
