import Foundation

/// How a tool reads to a person: its verb while running and after, its symbol, the size of what it
/// returned, and a one-line summary of a step's tools.
public enum ToolLabel {
    public static func verb(_ name: String, running: Bool) -> String {
        let (doing, did) = switch name {
        case "Read": (String(localized: "Reading"), String(localized: "Read"))
        case "Write": (String(localized: "Creating"), String(localized: "Created"))
        case "Edit", "MultiEdit": (String(localized: "Editing"), String(localized: "Edited"))
        case "Bash", "Shell": (String(localized: "Running"), String(localized: "Ran"))
        case "Grep": (String(localized: "Searching"), String(localized: "Searched"))
        case "Glob": (String(localized: "Finding"), String(localized: "Found"))
        case "LS": (String(localized: "Listing"), String(localized: "Listed"))
        case "WebSearch": (String(localized: "Searching the web for"), String(localized: "Searched the web for"))
        case "WebFetch": (String(localized: "Opening"), String(localized: "Opened"))
        default: (name, name)
        }
        return running ? doing : did
    }

    public static func symbol(_ name: String) -> String {
        switch name {
        case "Read", "Write", "Edit", "MultiEdit", "apply_patch": "doc.text"
        case "Bash", "Shell", "shell", "exec", "exec_command": "terminal"
        case "Skill": "sparkles"
        case "Task", "Agent": "person.2"
        case "TodoWrite", "update_plan": "checklist"
        case "Grep", "Glob": "magnifyingglass"
        case "LS": "folder"
        case "WebSearch", "WebFetch": "globe"
        default: "wrench.and.screwdriver"
        }
    }

    public static func size(name: String, output: String) -> String? {
        let count = output.split(separator: "\n").count
        return switch name {
        case "Read": count == 1 ? String(localized: "1 line") : String(localized: "\(count) lines")
        case "Glob", "LS": count == 1 ? String(localized: "1 item") : String(localized: "\(count) items")
        case "Grep": count == 1 ? String(localized: "1 result") : String(localized: "\(count) results")
        default: nil
        }
    }

    /// "Read 4 files, searched the web once, listed a folder" — groups in the order they first ran.
    public static func summary(of tools: [ToolPart]) -> String {
        var order: [Group] = []
        var counts: [Group: Int] = [:]
        for tool in tools {
            let group = Group(tool.name)
            if counts[group] == nil { order.append(group) }
            counts[group, default: 0] += 1
        }
        let phrases = order.map { $0.phrase(counts[$0]!) }
        guard let first = phrases.first else { return "" }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + phrases.dropFirst()).joined(separator: ", ")
    }

    private enum Group: Hashable {
        case read, created, edited, ran, searchedCode, searchedWeb, opened, listed, other

        init(_ name: String) {
            self = switch name {
            case "Read": .read
            case "Write": .created
            case "Edit", "MultiEdit": .edited
            case "Bash", "Shell": .ran
            case "Grep", "Glob": .searchedCode
            case "WebSearch": .searchedWeb
            case "WebFetch": .opened
            case "LS": .listed
            default: .other
            }
        }

        func phrase(_ n: Int) -> String {
            switch self {
            case .read: n == 1 ? String(localized: "read a file") : String(localized: "read \(n) files")
            case .created: n == 1 ? String(localized: "created a file") : String(localized: "created \(n) files")
            case .edited: n == 1 ? String(localized: "edited a file") : String(localized: "edited \(n) files")
            case .ran: n == 1 ? String(localized: "ran a command") : String(localized: "ran \(n) commands")
            case .searchedCode: n == 1 ? String(localized: "searched the code once") : String(localized: "searched the code \(n) times")
            case .searchedWeb: n == 1 ? String(localized: "searched the web once") : String(localized: "searched the web \(n) times")
            case .opened: n == 1 ? String(localized: "opened a page") : String(localized: "opened \(n) pages")
            case .listed: n == 1 ? String(localized: "listed a folder") : String(localized: "listed \(n) folders")
            case .other: n == 1 ? String(localized: "used 1 other tool") : String(localized: "used \(n) other tools")
            }
        }
    }
}
