import Foundation
import XBotBrain
import XBotTools
import XBotWorld

/// The xbot_* tools: xBot itself, through the same `Workspace` methods the window calls.
extension ToolHost {
    func xbot(_ tool: String, _ arguments: JSONValue, session: Session) async -> ToolResult {
        guard let workspace else { return .error(ToolClient.notRunning) }
        switch tool {
        case "xbot_projects": return projects(workspace)
        case "xbot_add_project": return addProject(workspace, arguments)
        case "xbot_chats": return chats(workspace, arguments)
        case "xbot_start_chat": return startChat(workspace, arguments)
        case "xbot_read_chat": return readChat(workspace, arguments)
        case "xbot_crew": return crew(workspace)
        case "xbot_hire": return hire(workspace, arguments)
        case "xbot_hand_off": return handOff(workspace, arguments, session: session)
        case "xbot_automations": return automations(workspace)
        case "xbot_save_automation": return saveAutomation(workspace, arguments)
        case "xbot_run_automation": return runAutomation(workspace, arguments)
        case "xbot_notes": return notes(workspace, arguments)
        case "xbot_write_note": return writeNote(workspace, arguments)
        case "xbot_settings": return settings(workspace)
        case "xbot_set_world": return setWorld(workspace, arguments)
        case "xbot_set_appearance": return setAppearance(arguments)
        case "xbot_remember": return remember(workspace, arguments, session: session)
        case "xbot_lessons": return lessons(workspace, session: session)
        case "xbot_ask": return await ask(workspace, arguments, session: session)
        default: return .error("There's no xBot tool called \(tool).")
        }
    }

    // MARK: Finding things by what the model calls them

    func project(_ workspace: Workspace, _ text: String?) -> Project? {
        guard let text else { return nil }
        return workspace.projects.first { $0.id.uuidString.caseInsensitiveCompare(text) == .orderedSame }
            ?? workspace.projects.first { $0.name.caseInsensitiveCompare(text) == .orderedSame }
            ?? workspace.projects.first { $0.path == (text as NSString).expandingTildeInPath }
    }

    func member(_ workspace: Workspace, _ name: String?) -> Agent? {
        guard let name else { return nil }
        return workspace.agents.first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            ?? workspace.agents.first { $0.id.uuidString.caseInsensitiveCompare(name) == .orderedSame }
    }

    func missing(_ what: String) -> ToolResult { .error("Missing \(what).") }

    // MARK: Projects and chats

    func projects(_ workspace: Workspace) -> ToolResult {
        guard !workspace.projects.isEmpty else { return .text("No projects yet. Chats without one work in xBot's Inbox folder.") }
        return .text(workspace.projects.map { "\($0.name) — \($0.path) (id \($0.id.uuidString))" }.joined(separator: "\n"))
    }

    func addProject(_ workspace: Workspace, _ arguments: JSONValue) -> ToolResult {
        guard let path = arguments.string("path") else { return missing("path") }
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .error("There's no folder at \(path).")
        }
        let project = workspace.addProject(at: URL(filePath: expanded, directoryHint: .isDirectory))
        return .text("Added \(project.name) (id \(project.id.uuidString)).")
    }

    func chats(_ workspace: Workspace, _ arguments: JSONValue) -> ToolResult {
        var chats = workspace.chats
        if let name = arguments.string("project") {
            guard let project = project(workspace, name) else { return .error("There's no project called \(name).") }
            chats = chats.filter { $0.projectID == project.id }
        }
        guard !chats.isEmpty else { return .text("No chats.") }
        let lines = chats.prefix(60).map { chat -> String in
            let who = workspace.agent(chat.agentID)?.name ?? chat.harness.displayName
            let place = chat.projectID.flatMap { id in workspace.projects.first { $0.id == id }?.name } ?? "Inbox"
            var line = "\(chat.id.uuidString) · \(chat.title) · with \(who) · \(place) · \(chat.updatedAt.formatted(.relative(presentation: .named)))"
            if workspace.isRunning(chat.id) { line += " · working" }
            if chat.automationID != nil { line += " · automation run" }
            return line
        }
        return .text(lines.joined(separator: "\n") + (chats.count > 60 ? "\n… and \(chats.count - 60) older." : ""))
    }

    func startChat(_ workspace: Workspace, _ arguments: JSONValue) -> ToolResult {
        guard let name = arguments.string("agent") else { return missing("agent") }
        guard let message = arguments.string("message") else { return missing("message") }
        guard let agent = member(workspace, name) else { return .error("There's no \(name) in the crew. xbot_crew lists them.") }
        var projectID = agent.projectID
        if let wanted = arguments.string("project") {
            guard let found = project(workspace, wanted) else { return .error("There's no project called \(wanted).") }
            projectID = found.id
        }
        guard let chat = workspace.startChat(with: agent, in: projectID, select: false) else {
            return .error("None of the agent CLIs is installed, so \(agent.name) can't start.")
        }
        guard workspace.send(message, in: chat.id) else { return .error("\(agent.name)'s chat started but the message couldn't be sent.") }
        return .text("Started a chat with \(agent.name) (id \(chat.id.uuidString)). They're working on it; xbot_read_chat shows how it goes.")
    }

    func readChat(_ workspace: Workspace, _ arguments: JSONValue) -> ToolResult {
        guard let text = arguments.string("id") else { return missing("id") }
        guard let id = UUID(uuidString: text), let chat = workspace.chat(id) else { return .error("There's no chat with id \(text).") }
        let messages = workspace.transcripts[id] ?? workspace.attempt { try workspace.store.messages(in: id) } ?? []
        let who = workspace.agent(chat.agentID)?.name ?? chat.harness.displayName
        var out = ["\(chat.title) — with \(who)\(workspace.isRunning(id) ? " (working now)" : "")"]
        for message in messages.suffix(30) {
            let speaker = message.role == .user ? "Person" : who
            let body = message.parts.compactMap { part -> String? in
                switch part {
                case .text(let text): text
                case .tool(let tool): "[\(tool.name) \(tool.summary)]"
                case .notice(let text): "(\(text))"
                case .failure(let reason): "(failed: \(reason))"
                case .image(let image): "[screenshot \(image.width)×\(image.height)]"
                case .approval(let approval): "[asked: \(approval.summary) — \(approval.state.rawValue)]"
                case .lesson(let lesson): "(learnt: \(lesson))"
                case .plan: "[a plan]"
                }
            }.joined(separator: "\n")
            out.append("\(speaker): \(body.count > 3000 ? String(body.prefix(3000)) + "…" : body)")
        }
        if messages.isEmpty { out.append("No messages yet.") }
        return .text(out.joined(separator: "\n\n"))
    }

    // MARK: The crew

    func crew(_ workspace: Workspace) -> ToolResult {
        let lines = workspace.agents.map { agent -> String in
            let boss = workspace.manager(of: agent.id)?.name ?? (agent.isHeadMaster ? "the person" : "HeadMaster")
            let doing = switch workspace.status(of: agent.id) {
            case .idle: "idle"
            case .done: "just finished"
            case .working(let activity, _): "working" + (activity.map { ": \($0)" } ?? "")
            }
            return "\(agent.name) — \(agent.role) · reports to \(boss) · \(agent.harness.displayName) · \(doing)"
        }
        return .text(lines.joined(separator: "\n"))
    }

    func hire(_ workspace: Workspace, _ arguments: JSONValue) -> ToolResult {
        guard let name = arguments.string("name")?.trimmingCharacters(in: .whitespacesAndNewlines) else { return missing("name") }
        guard let role = arguments.string("role") else { return missing("role") }
        guard member(workspace, name) == nil else { return .error("There's already a \(name) in the crew.") }
        var agent = workspace.hire()
        agent.name = name
        agent.role = role
        agent.instructions = arguments.string("instructions") ?? ""
        agent.managerID = workspace.suggestedManager(role: role, for: agent.id)
        workspace.saveAgent(agent)
        let boss = workspace.manager(of: agent.id)?.name ?? "HeadMaster"
        return .text("Hired \(name) (\(role)), reporting to \(boss).")
    }

    func handOff(_ workspace: Workspace, _ arguments: JSONValue, session: Session) -> ToolResult {
        guard let name = arguments.string("to") else { return missing("to") }
        guard let task = arguments.string("task") else { return missing("task") }
        guard let chat = workspace.chat(session.chatID) else { return .error("This chat is gone.") }
        guard let target = member(workspace, name) else { return .error("There's no \(name) in the crew.") }
        let caller = workspace.agent(session.agentID)
        if let caller, !workspace.team(of: caller.id).contains(where: { $0.id == target.id }) {
            return .error("\(target.name) isn't on your team. Use xbot_start_chat to ask them directly.")
        }
        guard let started = workspace.startChat(with: target, in: chat.projectID, select: false, handedFrom: chat.mode),
              workspace.send(caller.map { "From \($0.name): \(task)" } ?? task, in: started.id) else {
            return .error("Couldn't hand that to \(target.name).")
        }
        workspace.handoffOrigins[started.id] = chat.id
        post([.notice(Handoff.handedPrefix(target.name) + Workspace.title(from: task))], session: session)
        return .text("Handed to \(target.name) (chat \(started.id.uuidString)). xBot says so here when they finish.")
    }

    // MARK: Automations

    func automations(_ workspace: Workspace) -> ToolResult {
        guard !workspace.automations.isEmpty else { return .text("No automations yet.") }
        return .text(workspace.automations.map { automation -> String in
            let when = switch automation.trigger {
            case .manual: "run by hand"
            case .schedule(let schedule): Self.describe(schedule)
            }
            let last = automation.lastRunAt.map { "last run \($0.formatted(.relative(presentation: .named)))" } ?? "never run"
            return "\(automation.id.uuidString) · \(automation.name) · \(when) · \(automation.isEnabled ? "on" : "off") · \(last) · \(automation.steps.count) steps"
        }.joined(separator: "\n"))
    }

    static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    static func describe(_ schedule: AutomationSchedule) -> String {
        func time(_ h: Int, _ m: Int) -> String { String(format: "%02d:%02d", h, m) }
        return switch schedule {
        case .hourly(let minute): "hourly at :\(String(format: "%02d", minute))"
        case .daily(let h, let m): "daily at \(time(h, m))"
        case .weekdays(let h, let m): "weekdays at \(time(h, m))"
        case .weekly(let day, let h, let m): "\(weekdays[max(0, min(6, day - 1))])s at \(time(h, m))"
        }
    }

    func saveAutomation(_ workspace: Workspace, _ arguments: JSONValue) -> ToolResult {
        var automation: Automation
        if let id = arguments.string("id") {
            guard let found = UUID(uuidString: id).flatMap(workspace.automation) else { return .error("There's no automation with id \(id).") }
            automation = found
        } else {
            automation = workspace.newAutomation()
        }
        if let name = arguments.string("name") { automation.name = name }
        if let steps = arguments["steps"]?.arrayValue?.compactMap(\.stringValue).filter({ !$0.isEmpty }) {
            automation.steps = steps.map { AutomationStep(app: .anything, text: $0) }
        }
        guard !automation.steps.isEmpty else { return missing("steps") }
        if let schedule = arguments.string("schedule") {
            switch Self.trigger(schedule, time: arguments.string("time"), weekday: arguments.string("weekday")) {
            case .success(let trigger): automation.trigger = trigger
            case .failure(let problem): return .error(problem.message)
            }
        }
        if let wanted = arguments.string("project") {
            guard let found = project(workspace, wanted) else { return .error("There's no project called \(wanted).") }
            automation.projectID = found.id
        }
        if let cli = arguments.string("agent_cli") {
            guard let harness = HarnessKind(rawValue: cli.lowercased()) else { return .error("\(cli) isn't an agent CLI xBot drives.") }
            automation.harness = harness
        }
        workspace.saveAutomation(automation)
        return .text("Saved \(automation.name) (id \(automation.id.uuidString)).")
    }

    struct Problem: Error { let message: String }

    static func trigger(_ schedule: String, time: String?, weekday: String?) -> Result<Automation.Trigger, Problem> {
        let parts = (time ?? "").split(separator: ":").compactMap { Int($0) }
        let hour = parts.count >= 2 ? parts[0] : (parts.first ?? 9)
        let minute = parts.count >= 2 ? parts[1] : 0
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return .failure(Problem(message: "\(time ?? "") isn't a time (HH:MM).")) }
        switch schedule.lowercased() {
        case "manual": return .success(.manual)
        case "hourly": return .success(.schedule(.hourly(minute: parts.count >= 2 ? minute : (parts.first ?? 0) % 60)))
        case "daily": return .success(.schedule(.daily(hour: hour, minute: minute)))
        case "weekdays": return .success(.schedule(.weekdays(hour: hour, minute: minute)))
        case "weekly":
            guard let day = weekdays.firstIndex(of: (weekday ?? "monday").lowercased()) else {
                return .failure(Problem(message: "\(weekday ?? "") isn't a day of the week."))
            }
            return .success(.schedule(.weekly(weekday: day + 1, hour: hour, minute: minute)))
        default:
            return .failure(Problem(message: "\(schedule) isn't a schedule: manual, hourly, daily, weekdays or weekly."))
        }
    }

    func runAutomation(_ workspace: Workspace, _ arguments: JSONValue) -> ToolResult {
        guard let text = arguments.string("id") else { return missing("id") }
        guard let automation = UUID(uuidString: text).flatMap(workspace.automation)
            ?? workspace.automations.first(where: { $0.name.caseInsensitiveCompare(text) == .orderedSame }) else {
            return .error("There's no automation called \(text).")
        }
        guard let run = workspace.runAutomation(automation.id) else {
            return .error("\(automation.name) didn't start: it's running already, its agent CLI isn't installed, or it has no steps.")
        }
        return .text("Started \(automation.name) (run chat \(run.id.uuidString)).")
    }

    // MARK: Notes

    func notes(_ workspace: Workspace, _ arguments: JSONValue) -> ToolResult {
        guard let name = arguments.string("project") else { return missing("project") }
        guard let project = project(workspace, name) else { return .error("There's no project called \(name).") }
        let notes = workspace.notes(for: project)
        notes.reload()
        guard !notes.notes.isEmpty else { return .text("\(project.name) has no notes yet (they live in \(notes.notesFolder.path)).") }
        return .text(notes.notes.map { "\($0.title) — notes/\($0.url.lastPathComponent)" }.joined(separator: "\n"))
    }

    func writeNote(_ workspace: Workspace, _ arguments: JSONValue) -> ToolResult {
        guard let name = arguments.string("project") else { return missing("project") }
        guard let title = arguments.string("name") else { return missing("name") }
        guard let body = arguments["text"]?.stringValue else { return missing("text") }
        guard let project = project(workspace, name) else { return .error("There's no project called \(name).") }
        let notes = workspace.notes(for: project)
        notes.reload()
        // The note's title is its first line, as the Notes page has it.
        let text = ProjectNotes.title(of: body).caseInsensitiveCompare(title) == .orderedSame ? body : "# \(title)\n\n\(body)"
        let existing = notes.notes.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }?.url
        do {
            let url = try ProjectNotes.write(text, to: existing, in: notes.notesFolder)
            notes.reload()
            return .text("\(existing == nil ? "Wrote" : "Replaced") \(title) — notes/\(url.lastPathComponent) in \(project.name).")
        } catch {
            return .error("Couldn't write the note: \(error.localizedDescription)")
        }
    }

    // MARK: Settings

    func settings(_ workspace: Workspace) -> ToolResult {
        let wallpaper = switch appearance.wallpaper {
        case .sunset: "sunset"
        case .desktop: "desktop"
        case .custom: "a picture of the person's"
        case .ascii: "text art"
        case .none: "none"
        }
        return .text("""
            World: \(workspace.workplace.rawValue) (\(workspace.workplace.title))
            Theme: \(appearance.theme.rawValue)
            Wallpaper: \(wallpaper)
            App icon: \(appearance.appIcon.rawValue)
            Font: \(appearance.fontFamily ?? "system")
            xBot tools in every chat: \(workspace.toolsInEveryChat ? "on" : "off")
            """)
    }

    func setWorld(_ workspace: Workspace, _ arguments: JSONValue) -> ToolResult {
        guard let name = arguments.string("name") else { return missing("name") }
        let squashed = name.lowercased().filter { !$0.isWhitespace }
        guard let world = WorkplaceSetting.allCases.first(where: {
            $0.rawValue.lowercased() == squashed || $0.title.lowercased().filter { !$0.isWhitespace } == squashed
        }) else {
            return .error("\(name) isn't a world. The worlds: \(WorkplaceSetting.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        workspace.workplace = world
        return .text("The crew moved to \(world.title).")
    }

    func setAppearance(_ arguments: JSONValue) -> ToolResult {
        var changed: [String] = []
        if let text = arguments.string("theme") {
            guard let theme = Appearance.Theme(rawValue: text.lowercased()) else { return .error("\(text) isn't a theme: dark, light or system.") }
            appearance.theme = theme
            changed.append("theme \(theme.rawValue)")
        }
        if let text = arguments.string("wallpaper") {
            switch text.lowercased() {
            case "sunset": appearance.wallpaper = .sunset
            case "desktop": appearance.wallpaper = .desktop
            case "none": appearance.wallpaper = .none
            default: return .error("\(text) isn't a wallpaper: sunset, desktop or none.")
            }
            changed.append("wallpaper \(text.lowercased())")
        }
        if let text = arguments.string("app_icon") {
            guard let icon = Appearance.AppIcon(rawValue: text.lowercased()) else { return .error("\(text) isn't an app icon: ink, rose, sunset or plum.") }
            appearance.appIcon = icon
            changed.append("app icon \(icon.rawValue)")
        }
        if let text = arguments.string("font") {
            if text.lowercased() == "system" {
                appearance.fontFamily = nil
            } else {
                guard let family = Appearance.fontFamilies().first(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) else {
                    return .error("There's no font family called \(text) on this Mac.")
                }
                appearance.fontFamily = family
            }
            changed.append("font \(text)")
        }
        return changed.isEmpty ? missing("what to change") : .text("Changed: \(changed.joined(separator: ", ")).")
    }

    // MARK: Experience

    func remember(_ workspace: Workspace, _ arguments: JSONValue, session: Session) -> ToolResult {
        guard let agentID = session.agentID, workspace.agent(agentID) != nil else {
            return .error("Only a crew member keeps lessons, and this chat isn't with one.")
        }
        guard let cue = arguments.string("cue") else { return missing("cue") }
        guard let text = arguments.string("lesson") else { return missing("lesson") }
        guard let evidence = arguments.string("evidence") else { return missing("evidence") }
        guard let confidence = arguments.string("confidence").flatMap({ Lesson.Confidence(rawValue: $0.lowercased()) }) else {
            return .error("confidence is low, medium or high.")
        }
        do {
            try workspace.experience.remember(Lesson(cue: cue, lesson: text, confidence: confidence, evidence: evidence), for: agentID)
        } catch {
            return .error("Couldn't keep the lesson: \(error.localizedDescription)")
        }
        post([.lesson("\(cue) → \(text)")], session: session)
        return .text("Kept for next time.")
    }

    func lessons(_ workspace: Workspace, session: Session) -> ToolResult {
        guard let agentID = session.agentID else { return .text("This chat isn't with a crew member, so there are no lessons.") }
        let rank: [Lesson.Confidence: Int] = [.high: 0, .medium: 1, .low: 2]
        let lessons = workspace.experience.lessons(of: agentID)
            .sorted { (rank[$0.confidence] ?? 3, $1.learnt) < (rank[$1.confidence] ?? 3, $0.learnt) }
        guard !lessons.isEmpty else { return .text("No lessons yet.") }
        return .text(lessons.map { "\($0.cue) → \($0.lesson) (\($0.confidence.rawValue); \($0.evidence))" }.joined(separator: "\n"))
    }

    // MARK: Asking

    func ask(_ workspace: Workspace, _ arguments: JSONValue, session: Session) async -> ToolResult {
        guard let question = arguments.string("question") else { return missing("question") }
        let options = arguments["options"]?.arrayValue?.compactMap(\.stringValue).filter { !$0.isEmpty } ?? []
        let text = options.isEmpty ? question : question + "\n\n" + options.map { "- \($0)" }.joined(separator: "\n")
        post([.text(text)], session: session)
        guard let answer = await workspace.questions.ask(in: session.chatID, timeout: questionTimeout) else {
            return .text("The person didn't answer (no reply in time, or the turn was stopped). Don't assume a yes.")
        }
        return .text("The person replied: \(answer)")
    }
}
