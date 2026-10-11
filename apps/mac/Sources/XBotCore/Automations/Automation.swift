import Foundation
import XBotBrain

/// A trigger, then plain-words steps, each aimed at an app or a connector; an agent carries them
/// out with full access. See the automations spec.
public struct Automation: Identifiable, Equatable, Sendable {
    public enum Trigger: Equatable, Sendable {
        case manual
        case schedule(AutomationSchedule)
    }

    public var id: UUID
    public var name: String
    public var trigger: Trigger
    public var steps: [AutomationStep]
    public var harness: HarnessKind
    public var model: String?
    public var effort: Effort?
    /// Where it works. Nil: xBot's Inbox folder.
    public var projectID: UUID?
    public var isEnabled: Bool
    public var lastRunAt: Date?
    public var createdAt: Date
    public var sortIndex: Int

    public init(
        id: UUID = UUID(), name: String, trigger: Trigger, steps: [AutomationStep], harness: HarnessKind = .claude,
        model: String? = nil, effort: Effort? = nil, projectID: UUID? = nil, isEnabled: Bool = true,
        lastRunAt: Date? = nil, createdAt: Date = .now, sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.steps = steps
        self.harness = harness
        self.model = model
        self.effort = effort
        self.projectID = projectID
        self.isEnabled = isEnabled
        self.lastRunAt = lastRunAt
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }

    /// When it should next run: after its last run, or after it was made. Nil for Run now only.
    public func nextRun(calendar: Calendar = .current) -> Date? {
        guard case .schedule(let schedule) = trigger else { return nil }
        return schedule.next(after: lastRunAt ?? createdAt, calendar: calendar)
    }

    public func isDue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, let next = nextRun(calendar: calendar) else { return false }
        return next <= now
    }
}

public enum AutomationSchedule: Codable, Equatable, Sendable {
    case hourly(minute: Int)
    case daily(hour: Int, minute: Int)
    case weekdays(hour: Int, minute: Int)
    /// `weekday`: 1 Sunday … 7 Saturday, as Calendar counts.
    case weekly(weekday: Int, hour: Int, minute: Int)

    /// The first time strictly after `date`.
    public func next(after date: Date, calendar: Calendar = .current) -> Date {
        let policy = Calendar.MatchingPolicy.nextTime
        switch self {
        case .hourly(let minute):
            return calendar.nextDate(after: date, matching: DateComponents(minute: minute, second: 0), matchingPolicy: policy) ?? date
        case .daily(let hour, let minute):
            return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: policy) ?? date
        case .weekly(let weekday, let hour, let minute):
            return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday),
                                     matchingPolicy: policy) ?? date
        case .weekdays(let hour, let minute):
            var candidate = date
            for _ in 0..<8 {
                candidate = calendar.nextDate(after: candidate, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                              matchingPolicy: policy) ?? candidate
                if !calendar.isDateInWeekend(candidate) { return candidate }
            }
            return candidate
        }
    }
}

public struct AutomationStep: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var app: AutomationApp
    public var text: String

    public init(id: UUID = UUID(), app: AutomationApp, text: String) {
        self.id = id
        self.app = app
        self.text = text
    }
}

/// What a step is aimed at: an app that comes with the Mac, a connector, or nothing in particular.
public enum AutomationApp: Hashable, Sendable {
    case mail, calendar, reminders, notes, messages, contacts, finder, safari, music, photos, maps, shortcuts
    case terminal, web, anything
    /// A claude.ai connector or MCP server, by name.
    case connector(String)

    /// The palette's apps, in order.
    public static let builtIn: [AutomationApp] = [
        .mail, .calendar, .reminders, .notes, .messages, .contacts, .finder, .safari, .music, .photos, .maps,
        .shortcuts, .terminal, .web, .anything,
    ]

    public var title: String {
        switch self {
        case .mail: "Mail"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .notes: "Notes"
        case .messages: "Messages"
        case .contacts: "Contacts"
        case .finder: "Finder"
        case .safari: "Safari"
        case .music: "Music"
        case .photos: "Photos"
        case .maps: "Maps"
        case .shortcuts: "Shortcuts"
        case .terminal: String(localized: "Terminal")
        case .web: String(localized: "Web")
        case .anything: String(localized: "Anything")
        case .connector(let name): name
        }
    }

    /// The app on disk, for its icon. Nil for connectors, Web and Anything.
    public var bundlePath: String? {
        switch self {
        case .finder: "/System/Library/CoreServices/Finder.app"
        case .terminal: "/System/Applications/Utilities/Terminal.app"
        case .safari: "/Applications/Safari.app"
        case .connector, .web, .anything: nil
        default: "/System/Applications/\(title).app"
        }
    }

    /// Saved as a string: "mail", or "connector:Gmail".
    public var storageKey: String {
        if case .connector(let name) = self { return "connector:" + name }
        return String(describing: self)
    }

    public init?(storageKey: String) {
        if storageKey.hasPrefix("connector:") {
            self = .connector(String(storageKey.dropFirst("connector:".count)))
        } else if let app = Self.builtIn.first(where: { $0.storageKey == storageKey }) {
            self = app
        } else {
            return nil
        }
    }

    /// How an agent reaches it from a shell. Nil: nothing special to say.
    var howTo: String? {
        switch self {
        case .mail, .calendar, .reminders, .notes, .messages, .contacts, .music, .photos, .safari, .finder:
            "\(title): script it with `osascript` (AppleScript, or JXA with `-l JavaScript`), e.g. `osascript -e 'tell application \"\(title)\" to …'`."
        case .maps: "Maps: open places and directions with `open \"maps://?q=…\"` or `open \"maps://?daddr=…\"`."
        case .shortcuts: "Shortcuts: `shortcuts list` shows the person's shortcuts; `shortcuts run \"Name\"` runs one (`-i` for input)."
        case .terminal: "Terminal: run commands directly in your shell."
        case .web: "Web: search and fetch pages with your web tools, or `curl`."
        case .connector(let name): "\(name) connector: use its MCP tools (named after \(name)); they're already connected."
        case .anything: nil
        }
    }

    var label: String {
        if case .connector(let name) = self { return "\(name) connector" }
        return title
    }
}

/// The one turn an automation runs as.
public enum AutomationPrompt {
    public static func make(_ automation: Automation) -> String {
        let steps = automation.steps.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var text = """
            You are running the automation "\(automation.name)" for the person who owns this Mac, with full access \
            to it. Do the steps below in order, on their behalf, without stopping to ask: they set this up to run \
            by itself. If a step can't be done, say why and carry on with the rest where that makes sense.

            Steps:

            """
        for (index, step) in steps.enumerated() {
            text += "\(index + 1). [\(step.app.label)] \(step.text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        }
        var seen = Set<String>()
        let howTos = steps.compactMap { step -> String? in
            guard let how = step.app.howTo, seen.insert(step.app.storageKey).inserted else { return nil }
            return "- " + how
        }
        if !howTos.isEmpty {
            text += "\nHow to reach the apps:\n" + howTos.joined(separator: "\n") + "\n"
        }
        text += "\nWhen you're done, report briefly what you did in each step."
        return text
    }
}
