import Foundation

/// The few edits xBot makes to `~/.codex/config.toml`: one `enabled` value in one table. Codex has
/// no command for switching a plugin, MCP server or skill off, so the file is the switch — and it is
/// the person's file, full of their own settings and comments, so nothing else in it may change.
public enum CodexConfig {
    /// Sets `enabled` in the table `[header]` (e.g. `plugins."github@openai-curated"`), adding the
    /// line, or the table at the end, when they are missing.
    public static func setEnabled(_ enabled: Bool, table header: String, in toml: String) -> String {
        var lines = toml.components(separatedBy: "\n")
        let value = "enabled = \(enabled)"
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(header)]" }) else {
            var text = toml
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            if !text.isEmpty, !text.hasSuffix("\n\n") { text += "\n" }
            return text + "[\(header)]\n\(value)\n"
        }
        let end = lines[(start + 1)...].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        if let existing = lines[(start + 1)..<end].firstIndex(where: { assignment($0)?.key == "enabled" }) {
            lines[existing] = value
        } else {
            lines.insert(value, at: start + 1)
        }
        return lines.joined(separator: "\n")
    }

    /// Sets `enabled` on the `[[skills.config]]` entry for `path`, adding the entry when missing.
    public static func setSkillEnabled(_ enabled: Bool, path: String, in toml: String) -> String {
        var lines = toml.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            guard lines[index].trimmingCharacters(in: .whitespaces) == "[[skills.config]]" else { index += 1; continue }
            let end = lines[(index + 1)...].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
            let body = lines[(index + 1)..<end]
            if body.contains(where: { line in assignment(line).map { $0.key == "path" && unquote($0.value) == path } ?? false }) {
                if let existing = body.firstIndex(where: { assignment($0)?.key == "enabled" }) {
                    lines[existing] = "enabled = \(enabled)"
                } else {
                    lines.insert("enabled = \(enabled)", at: end)
                }
                return lines.joined(separator: "\n")
            }
            index = end
        }
        var text = toml
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty, !text.hasSuffix("\n\n") { text += "\n" }
        return text + "[[skills.config]]\npath = \(quote(path))\nenabled = \(enabled)\n"
    }

    /// A TOML table header for a key that may need quoting: `plugins."a@b"`, `mcp_servers.name`.
    public static func header(_ section: String, _ key: String) -> String {
        let bare = key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return "\(section).\(bare ? key : quote(key))"
    }

    static func assignment(_ line: String, separator: Character = "=") -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let split = trimmed.firstIndex(of: separator) else { return nil }
        let key = trimmed[..<split].trimmingCharacters(in: .whitespaces)
        let value = trimmed[trimmed.index(after: split)...].trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : (key, value)
    }

    static func unquote(_ value: String) -> String {
        for q in ["\"", "'"] where value.count >= 2 && value.hasPrefix(q) && value.hasSuffix(q) {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
        }
        return value
    }

    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
