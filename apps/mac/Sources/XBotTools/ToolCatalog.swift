import Foundation

/// Every tool the xbot MCP server offers, as the model sees them. The descriptions are tool
/// guidance (Harness2's term): precise, short, and saying when to use which.
public enum ToolCatalog {
    static func text(_ description: String) -> JSONValue { ["type": "string", "description": .string(description)] }
    static func number(_ description: String) -> JSONValue { ["type": "number", "description": .string(description)] }
    static func choice(_ description: String, _ values: [String]) -> JSONValue {
        ["type": "string", "description": .string(description), "enum": .array(values.map(JSONValue.string))]
    }
    static func list(_ description: String) -> JSONValue {
        ["type": "array", "items": ["type": "string"], "description": .string(description)]
    }

    public static let all: [ToolSpec] = xbot + mac

    public static let xbot: [ToolSpec] = [
        ToolSpec(name: "xbot_projects", description: "List xBot's projects: name, folder and id.", properties: [:], required: []),
        ToolSpec(name: "xbot_add_project", description: "Add a folder on this Mac to xBot as a project.",
                 properties: ["path": text("The folder's full path (~ allowed).")], required: ["path"]),
        ToolSpec(name: "xbot_chats", description: "List xBot's chats, newest first: id, title, who it's with, project, and whether a turn is running.",
                 properties: ["project": text("Only this project's chats (name or id).")], required: []),
        ToolSpec(name: "xbot_start_chat", description: "Start a new chat with a crew member and send them a message. They work on it in their own chat; returns its id.",
                 properties: [
                    "agent": text("The crew member's name."),
                    "project": text("The project to work in (name or id). Default: their home project."),
                    "message": text("What to ask them: clear and self-contained."),
                 ], required: ["agent", "message"]),
        ToolSpec(name: "xbot_read_chat", description: "Read a chat's recent messages (from xbot_chats).",
                 properties: ["id": text("The chat's id.")], required: ["id"]),
        ToolSpec(name: "xbot_crew", description: "List the crew: name, role, who they report to, their agent CLI, and what they're doing now.", properties: [:], required: []),
        ToolSpec(name: "xbot_hire", description: "Hire a new crew member. They report where their role suggests.",
                 properties: [
                    "name": text("Their name."),
                    "role": text("One line: what they do."),
                    "instructions": text("How they work (optional)."),
                 ], required: ["name", "role"]),
        ToolSpec(name: "xbot_hand_off", description: "Hand a task to someone on your team. They start in their own chat in this project; xBot tells you here when they finish.",
                 properties: [
                    "to": text("The crew member's name."),
                    "task": text("A clear, self-contained task: what to do, where, and what done looks like."),
                 ], required: ["to", "task"]),
        ToolSpec(name: "xbot_automations", description: "List automations: id, name, schedule, whether it's on, and the last run.", properties: [:], required: []),
        ToolSpec(name: "xbot_save_automation", description: "Create an automation, or change one (with id): plain-words steps an agent carries out with full access, run by hand or on a schedule.",
                 properties: [
                    "id": text("An existing automation's id, to change it."),
                    "name": text("Its name."),
                    "steps": list("What to do, one plain-words step each."),
                    "schedule": choice("When it runs. Default: manual.", ["manual", "hourly", "daily", "weekdays", "weekly"]),
                    "time": text("For daily, weekdays and weekly: HH:MM (24-hour). For hourly: the minute, MM."),
                    "weekday": choice("For weekly.", ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]),
                    "project": text("Where it works (name or id). Default: xBot's Inbox."),
                    "agent_cli": choice("Which agent CLI runs it.", ["claude", "codex", "antigravity", "copilot"]),
                 ], required: ["name", "steps"]),
        ToolSpec(name: "xbot_run_automation", description: "Run an automation now (by id or name).",
                 properties: ["id": text("The automation's id or name.")], required: ["id"]),
        ToolSpec(name: "xbot_notes", description: "List a project's notes (markdown files in its notes folder), with their file names.",
                 properties: ["project": text("The project (name or id).")], required: ["project"]),
        ToolSpec(name: "xbot_write_note", description: "Write a note in a project: creates it, or replaces the note with that name.",
                 properties: [
                    "project": text("The project (name or id)."),
                    "name": text("The note's name (its title)."),
                    "text": text("The whole note, in Markdown."),
                 ], required: ["project", "name", "text"]),
        ToolSpec(name: "xbot_settings", description: "xBot's settings: the crew's world, appearance, and whether xBot tools are in every chat.", properties: [:], required: []),
        ToolSpec(name: "xbot_set_world", description: "Move the crew to another world.",
                 properties: ["name": choice("The world.", ["village", "skyRealm", "underwater", "moonbase", "enchantedForest"])],
                 required: ["name"]),
        ToolSpec(name: "xbot_set_appearance", description: "Change how xBot looks. Give only what changes.",
                 properties: [
                    "theme": choice("Light or dark.", ["dark", "light", "system"]),
                    "wallpaper": choice("The picture behind the main screen.", ["sunset", "desktop", "none"]),
                    "app_icon": choice("The app icon's colour.", ["ink", "rose", "sunset", "plum"]),
                    "font": text("A font family on this Mac, or \"system\"."),
                 ], required: []),
        ToolSpec(name: "xbot_remember", description: "Keep a lesson for next time: something general you learnt (not task facts). Call once, at the end of a task.",
                 properties: [
                    "cue": text("When it applies: \"When Xcode asks to trust a package\"."),
                    "lesson": text("What to do: \"Choose Trust and Enable\"."),
                    "confidence": choice("How sure you are.", ["low", "medium", "high"]),
                    "evidence": text("One line: what happened that shows it."),
                 ], required: ["cue", "lesson", "confidence", "evidence"]),
        ToolSpec(name: "xbot_lessons", description: "What you've learnt before: your lessons, with confidence.", properties: [:], required: []),
        ToolSpec(name: "xbot_ask", description: "Ask the person something in this chat and wait for their reply (up to 10 minutes). Use before anything destructive or outward you'd do with your own shell.",
                 properties: [
                    "question": text("The question, in one or two sentences."),
                    "options": list("Answers to offer (optional)."),
                 ], required: ["question"]),
    ]

    public static let mac: [ToolSpec] = [
        ToolSpec(name: "mac_screenshot", description: "See the Mac: a screenshot of the main display, or of an app's front window. The person sees it in the chat too. Take one to check what an action did.",
                 properties: ["app": text("An app's name or bundle id, for just its front window.")], required: []),
        ToolSpec(name: "mac_ui", description: "Read the front (or named) app's window through Accessibility: each element's id, role, title, value and frame. Prefer this and mac_click(element) over coordinates.",
                 properties: ["app": text("An app's name or bundle id. Default: the frontmost app.")], required: []),
        ToolSpec(name: "mac_click", description: "Click an element from mac_ui by its id (pressed through Accessibility), or a point on screen (x, y in screen points, top-left origin).",
                 properties: ["element": text("An id from mac_ui, like \"e12\"."), "x": number("Screen x."), "y": number("Screen y.")],
                 required: []),
        ToolSpec(name: "mac_type", description: "Type text into whatever has keyboard focus.",
                 properties: ["text": text("The text to type.")], required: ["text"]),
        ToolSpec(name: "mac_keys", description: "Press a key or combination: \"return\", \"escape\", \"tab\", \"cmd+s\", \"cmd+shift+4\", \"down\".",
                 properties: ["combo": text("Modifiers (cmd, shift, option, control, fn) and one key, joined by +.")], required: ["combo"]),
        ToolSpec(name: "mac_scroll", description: "Scroll where the pointer is (or at x, y): positive dy scrolls down, positive dx right, in points.",
                 properties: ["dx": number("Horizontal points."), "dy": number("Vertical points."), "x": number("Screen x."), "y": number("Screen y.")],
                 required: []),
        ToolSpec(name: "mac_open", description: "Open an app (name or bundle id), a URL, or a file or folder (path).",
                 properties: ["target": text("\"Safari\", \"com.apple.TextEdit\", \"https://…\", or \"~/Documents/report.pdf\".")],
                 required: ["target"]),
        ToolSpec(name: "mac_apps", description: "The running apps: name, bundle id, and which is frontmost.", properties: [:], required: []),
        ToolSpec(name: "mac_quit", description: "Quit an app. The person is asked first.",
                 properties: ["app": text("The app's name or bundle id.")], required: ["app"]),
    ]
}
