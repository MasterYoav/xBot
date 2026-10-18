import Foundation
import XBotTools

/// An action that needs the person's say-so before it runs.
public struct Risk: Equatable, Sendable {
    /// Which rule caught it (the spec's list, and `ApprovalPart.risk`).
    public enum Kind: String, Sendable, CaseIterable { case delete, send, push, purchase, quit, settings }

    public var kind: Kind
    /// What the agent wants to do, as a verb phrase: "delete files", "quit Safari".
    public var summary: String
    /// The command or call, as it will run.
    public var detail: String

    public init(_ kind: Kind, _ summary: String, detail: String) {
        self.kind = kind
        self.summary = summary
        self.detail = detail
    }

    /// The card the person answers: "Forge wants to quit Safari".
    public func approval(agent: String) -> ApprovalPart {
        ApprovalPart(agent: agent, summary: String(localized: "\(agent) wants to \(summary)"), detail: detail,
                     risk: kind.rawValue)
    }
}

/// Agentic Mode's guardrails (see the spec's Approvals): deleting, sending, pushing, buying,
/// quitting apps and changing system settings ask first; everything else just runs. Pure, so
/// every rule is tested both ways.
///
/// These are a seatbelt for an agent acting in good faith, not a sandbox: a determined shell
/// command can always be spelled so no rule sees it. The CLI's own permission mode still applies.
public enum RiskRules {
    /// What's on screen when a Mac-control tool acts: the frontmost app, its front window, and the
    /// element being clicked (from `mac_ui`), when known.
    public struct Screen: Equatable, Sendable {
        public var app: String?
        public var bundleID: String?
        public var windowTitle: String?
        public var elementTitle: String?

        public init(app: String? = nil, bundleID: String? = nil, windowTitle: String? = nil, elementTitle: String? = nil) {
            self.app = app
            self.bundleID = bundleID
            self.windowTitle = windowTitle
            self.elementTitle = elementTitle
        }
    }

    // MARK: xBot's own tools

    static let acting: Set<String> = ["mac_click", "mac_type", "mac_keys", "mac_scroll"]
    static let settingsBundleID = "com.apple.systempreferences"
    static let mailBundleID = "com.apple.mail"
    static let messagesBundleID = "com.apple.MobileSMS"
    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "org.alacritty", "co.zeit.hyper", "com.github.wez.wezterm",
    ]

    /// A call to one of xBot's tools, with what's on screen.
    public static func check(tool: String, arguments: JSONValue, screen: Screen) -> Risk? {
        let detail = "\(tool) \(arguments.compactText)"
        if tool == "mac_quit" {
            let app = arguments.string("app") ?? String(localized: "an app")
            return Risk(.quit, String(localized: "quit \(app)"), detail: detail)
        }
        if tool.contains("delete") || tool.contains("remove") {
            return Risk(.delete, String(localized: "delete something in xBot"), detail: detail)
        }
        guard acting.contains(tool) else { return nil }

        if screen.bundleID == settingsBundleID || screen.app == "System Settings" {
            return Risk(.settings, String(localized: "change System Settings"), detail: detail)
        }
        let combo = arguments.string("combo").map(KeyCombo.normalised)
        let isMail = screen.bundleID == mailBundleID || screen.app == "Mail"
        let isMessages = screen.bundleID == messagesBundleID || screen.app == "Messages"
        let commandReturn = combo.map { $0.modifiers == ["cmd"] && ["return", "enter"].contains($0.key) } ?? false
        let plainReturn = combo.map { $0.modifiers.isEmpty && ["return", "enter"].contains($0.key) } ?? false
        let where_ = screen.app ?? String(localized: "an app")

        // Sending.
        if tool == "mac_keys", isMail || isMessages, commandReturn {
            return Risk(.send, String(localized: "send a message in \(where_)"), detail: detail)
        }
        if tool == "mac_keys", isMail, combo.map({ $0.modifiers == ["cmd", "shift"] && $0.key == "d" }) == true {
            return Risk(.send, String(localized: "send a message in \(where_)"), detail: detail)
        }
        if isMessages, tool == "mac_keys" && plainReturn
            || tool == "mac_type" && (arguments.string("text") ?? "").contains(where: \.isNewline) {
            return Risk(.send, String(localized: "send a message in \(where_)"), detail: detail)
        }
        if tool == "mac_click", let element = screen.elementTitle, isSendButton(element) {
            return Risk(.send, String(localized: "press Send in \(where_)"), detail: detail)
        }

        // Buying.
        let confirms = tool == "mac_click" || tool == "mac_keys" && plainReturn
        if confirms, saysBuying(screen.elementTitle) || saysBuying(screen.windowTitle) {
            return Risk(.purchase, String(localized: "buy something in \(where_)"), detail: detail)
        }

        // A command typed into a terminal is a command.
        if tool == "mac_type", let bundle = screen.bundleID, terminalBundleIDs.contains(bundle),
           let text = arguments.string("text"), let risk = check(shell: text) {
            return Risk(risk.kind, risk.summary, detail: detail)
        }
        return nil
    }

    static func isSendButton(_ title: String) -> Bool {
        let words = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["send", "send message", "send now", "send email"].contains(words)
    }

    static func saysBuying(_ text: String?) -> Bool {
        guard let text else { return false }
        let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return !words.isDisjoint(with: ["checkout", "buy", "pay", "payment", "order", "purchase"])
    }

    // MARK: Claude Code's own tools, through the PreToolUse hook

    /// A tool the CLI itself runs: its shell, and other MCP servers' tools that send or delete.
    public static func check(hookTool name: String, input: JSONValue) -> Risk? {
        if name == "Bash" { return input.string("command").flatMap { check(shell: $0) } }
        // xBot's own are checked by the app when they run.
        guard name.hasPrefix("mcp__"), !name.hasPrefix("mcp__xbot__") else { return nil }
        let words = Set(name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let detail = "\(name) \(input.compactText)"
        if !words.isDisjoint(with: ["send", "publish"]) {
            return Risk(.send, String(localized: "send something with \(name)"), detail: detail)
        }
        if !words.isDisjoint(with: ["delete", "remove", "trash", "destroy"]) {
            return Risk(.delete, String(localized: "delete something with \(name)"), detail: detail)
        }
        if !words.isDisjoint(with: ["purchase", "buy", "pay", "checkout"]) {
            return Risk(.purchase, String(localized: "buy something with \(name)"), detail: detail)
        }
        if words.contains("push") {
            return Risk(.push, String(localized: "push with \(name)"), detail: detail)
        }
        return nil
    }

    // MARK: Shell commands

    /// A shell command line: each command in it (after `;`, `&&`, `|`, inside `$(…)`) is checked.
    public static func check(shell command: String) -> Risk? {
        for words in ShellWords.commands(in: command) {
            if let (kind, summary) = check(words: words) { return Risk(kind, summary, detail: command) }
        }
        return nil
    }

    private static let wrappers: Set<String> = ["env", "nohup", "time", "command", "exec", "nice", "caffeinate", "xargs", "timeout"]

    static func check(words: [String]) -> (Risk.Kind, String)? {
        var words = words
        // Leading assignments: FOO=1 rm x.
        while let first = words.first, isAssignment(first) { words.removeFirst() }
        guard let first = words.first else { return nil }
        let name = (first as NSString).lastPathComponent
        let rest = Array(words.dropFirst())

        if name == "sudo" {
            if let inner = check(words: skipOptions(rest, taking: ["-u", "-g", "-h", "-p", "-C", "-U", "-D", "-r", "-t"])) { return inner }
            return (.settings, String(localized: "run a command as administrator"))
        }
        if wrappers.contains(name) {
            let taking: Set<String> = name == "xargs" ? ["-I", "-J", "-n", "-L", "-P", "-s", "-E", "-R", "-S"] : ["-n", "-s", "-k"]
            var inner = skipOptions(rest, taking: taking)
            while let head = inner.first, isAssignment(head) { inner.removeFirst() }
            if name == "timeout", let head = inner.first, Double(head.trimmingCharacters(in: .letters)) != nil { inner.removeFirst() }
            return check(words: inner)
        }

        let deleting = String(localized: "delete files")
        switch name {
        case "rm", "rmdir", "unlink", "shred", "srm", "trash":
            return (.delete, deleting)
        case "find":
            if rest.contains("-delete") { return (.delete, deleting) }
            if let index = rest.firstIndex(where: { $0 == "-exec" || $0 == "-execdir" || $0 == "-ok" }) {
                let inner = rest[(index + 1)...].prefix { $0 != ";" && $0 != "+" && $0 != "\\;" }
                return check(words: Array(inner))
            }
        case "mv":
            if let last = rest.last, last.contains(".Trash") { return (.delete, String(localized: "move files to the Bin")) }
        case "git":
            return checkGit(rest)
        case "gh":
            if rest.contains("delete") { return (.delete, String(localized: "delete something on GitHub")) }
        case "osascript":
            let script = rest.joined(separator: " ").lowercased()
            let tokens = Set(script.split(whereSeparator: { !$0.isLetter }).map(String.init))
            if tokens.contains("send") { return (.send, String(localized: "send a message")) }
            if tokens.contains("quit") { return (.quit, String(localized: "quit an app")) }
            if tokens.contains("delete") { return (.delete, String(localized: "delete something")) }
        case "mail", "mailx", "sendmail", "mutt", "msmtp":
            return (.send, String(localized: "send an email"))
        case "defaults":
            return checkDefaults(rest)
        case "killall", "pkill", "kill":
            return (.quit, String(localized: "quit an app"))
        case "shutdown", "reboot", "halt":
            return (.settings, String(localized: "restart or shut down the Mac"))
        case "csrutil", "spctl", "tccutil", "nvram", "softwareupdate", "dscl", "fdesetup", "kextload":
            return (.settings, String(localized: "change system settings"))
        case "networksetup", "systemsetup":
            if rest.contains(where: { $0.hasPrefix("-set") || $0.hasPrefix("-remove") || $0.hasPrefix("-delete") }) {
                return (.settings, String(localized: "change system settings"))
            }
        case "pmset":
            if !rest.contains("-g") { return (.settings, String(localized: "change system settings")) }
        case "scutil":
            if rest.contains("--set") { return (.settings, String(localized: "change system settings")) }
        case "launchctl":
            if let sub = rest.first, !["list", "print", "print-disabled", "blame", "help", "version"].contains(sub) {
                return (.settings, String(localized: "change what runs in the background"))
            }
        case "mas":
            if rest.first == "purchase" { return (.purchase, String(localized: "buy an app")) }
        default:
            break
        }
        return nil
    }

    static func checkGit(_ arguments: [String]) -> (Risk.Kind, String)? {
        // Global options before the subcommand: -C <path>, -c <key=value>, --git-dir=…
        var rest = arguments[...]
        while let head = rest.first, head.hasPrefix("-") {
            rest = rest.dropFirst()
            if ["-C", "-c", "--git-dir", "--work-tree", "--namespace"].contains(head) { rest = rest.dropFirst() }
        }
        guard let sub = rest.first else { return nil }
        let options = Array(rest.dropFirst())
        let discarding = String(localized: "throw away changes in git")
        switch sub {
        case "push":
            return (.push, String(localized: "push to a git remote"))
        case "clean":
            if options.contains("-n") || options.contains("--dry-run") { return nil }
            return (.delete, String(localized: "delete untracked files"))
        case "reset":
            if options.contains("--hard") { return (.delete, discarding) }
        case "branch":
            if options.contains("-D") || options.contains("--delete") && options.contains("--force") {
                return (.delete, String(localized: "delete a git branch"))
            }
        case "checkout":
            if options.contains("--") || options.contains(".") { return (.delete, discarding) }
        case "restore":
            if !options.contains("--staged") || options.contains("--worktree") { return (.delete, discarding) }
        case "stash":
            if options.first == "drop" || options.first == "clear" { return (.delete, String(localized: "delete stashed changes")) }
        default:
            break
        }
        return nil
    }

    /// xBot's own domain may change; anything else is the Mac's or another app's settings.
    static func checkDefaults(_ arguments: [String]) -> (Risk.Kind, String)? {
        let words = arguments.filter { $0 != "-currentHost" }
        guard let sub = words.first, ["write", "delete", "rename", "import"].contains(sub) else { return nil }
        let domain = words.dropFirst().first
        if domain == "dev.xbot.app" { return nil }
        return (.settings, String(localized: "change settings with defaults"))
    }

    static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        return word[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Drops leading options (and the values of those in `taking`).
    static func skipOptions(_ words: [String], taking: Set<String>) -> [String] {
        var rest = words[...]
        while let head = rest.first, head.hasPrefix("-") {
            rest = rest.dropFirst()
            if head == "--" { break }
            if taking.contains(head) { rest = rest.dropFirst() }
        }
        return Array(rest)
    }
}

/// A shell line split into its commands, each as words with quotes removed. Enough of POSIX sh to
/// find the commands; not an interpreter.
enum ShellWords {
    static func commands(in line: String) -> [[String]] {
        var commands: [[String]] = []
        var words: [String] = []
        var word = ""
        var inWord = false
        var quote: Character?
        var chars = Array(line)[...]

        func endWord() {
            if inWord { words.append(word) }
            word = ""
            inWord = false
        }
        func endCommand() {
            endWord()
            if !words.isEmpty { commands.append(words) }
            words = []
        }

        while let c = chars.first {
            chars = chars.dropFirst()
            if let q = quote {
                if c == q { quote = nil; continue }
                if q == "\"" && c == "\\", let next = chars.first { word.append(next); chars = chars.dropFirst(); continue }
                // A command substitution inside double quotes still runs.
                if q == "\"" && (c == "`" || c == "$" && chars.first == "(") {
                    if c == "$" { chars = chars.dropFirst() }
                    let saved = (words, word, inWord)
                    words = []; word = ""; inWord = false
                    var depth = 1
                    var inner = ""
                    while let d = chars.first, depth > 0 {
                        chars = chars.dropFirst()
                        if c == "`" ? d == "`" : d == ")" { depth -= 1; if depth == 0 { break } }
                        if c == "$" && d == "(" { depth += 1 }
                        inner.append(d)
                    }
                    commands += Self.commands(in: inner)
                    (words, word, inWord) = saved
                    continue
                }
                word.append(c)
                continue
            }
            switch c {
            case "'", "\"":
                quote = c
                inWord = true
            case "\\":
                if let next = chars.first { word.append(next); inWord = true; chars = chars.dropFirst() }
            case " ", "\t":
                endWord()
            case "\n", ";", "&", "|", "(", ")", "`", "{", "}":
                endCommand()
            case "$" where chars.first == "(":
                chars = chars.dropFirst()
                endCommand()
            case ">", "<":
                // A redirection's target is a file name, not a word of the command.
                endWord()
                while chars.first == ">" || chars.first == "&" { chars = chars.dropFirst() }
                while chars.first == " " { chars = chars.dropFirst() }
                while let d = chars.first, !" \t\n;&|".contains(d) { chars = chars.dropFirst() }
            default:
                word.append(c)
                inWord = true
            }
        }
        endCommand()
        return commands
    }
}

/// A key combination as typed to `mac_keys`: "cmd+shift+4", "Return", "⌘↩".
public struct KeyCombo: Equatable, Sendable {
    /// Of "cmd", "shift", "option", "control", "fn", in that order.
    public var modifiers: [String]
    /// Lowercased: "return", "s", "4", "left", "f5".
    public var key: String

    static let modifierOrder = ["cmd", "shift", "option", "control", "fn"]
    static let modifierNames: [String: String] = [
        "cmd": "cmd", "command": "cmd", "⌘": "cmd", "meta": "cmd", "super": "cmd",
        "shift": "shift", "⇧": "shift",
        "option": "option", "opt": "option", "alt": "option", "⌥": "option",
        "control": "control", "ctrl": "control", "ctl": "control", "⌃": "control",
        "fn": "fn",
    ]
    static let keyNames: [String: String] = [
        "↩": "return", "enter": "enter", "⏎": "return", "ret": "return", "esc": "escape", "⎋": "escape",
        "del": "delete", "backspace": "delete", "⌫": "delete", "forwarddelete": "forwarddelete", "⌦": "forwarddelete",
        "⇥": "tab", "spacebar": "space", "␣": "space", "arrowup": "up", "arrowdown": "down", "arrowleft": "left",
        "arrowright": "right", "↑": "up", "↓": "down", "←": "left", "→": "right", "pgup": "pageup", "pgdn": "pagedown",
    ]

    /// Separators may be "+", "-" between words, or spaces; symbols may be run together ("⌘↩").
    public static func normalised(_ text: String) -> KeyCombo {
        var parts: [String] = []
        let lowered = text.lowercased().trimmingCharacters(in: .whitespaces)
        for chunk in lowered.split(whereSeparator: { $0 == "+" || $0 == " " }) {
            var rest = String(chunk)
            // Leading modifier symbols: "⌘⇧4".
            while let first = rest.first, rest.count > 1, let name = modifierNames[String(first)] {
                parts.append(name)
                rest.removeFirst()
            }
            parts.append(rest)
        }
        if lowered.hasSuffix("+") { parts.append("+") }
        var modifiers: Set<String> = []
        var key = ""
        parts.removeAll(where: \.isEmpty)
        // Every part but the last that names a modifier is one; the last is the key ("shift" on its
        // own presses Shift).
        for (index, part) in parts.enumerated() {
            if index < parts.count - 1, let modifier = modifierNames[part] {
                modifiers.insert(modifier)
            } else {
                key = keyNames[part] ?? part
            }
        }
        return KeyCombo(modifiers: modifierOrder.filter(modifiers.contains), key: key)
    }
}
