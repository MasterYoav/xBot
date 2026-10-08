import Foundation

/// One line of a CLI's JSON stream, as a dictionary, or nil for anything else. A harness prints
/// banners and warnings between its JSON lines; those are not ours to fail on.
func jsonObject(_ line: String) -> [String: Any]? {
    guard line.first == "{" else { return nil }
    return (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
}

/// What a tool call is about, on one line: its file, command, pattern or address.
func summary(of input: Any?) -> String {
    guard let input = input as? [String: Any] else { return "" }
    for key in ["file_path", "path", "command", "pattern", "url", "query", "description"] {
        if let value = input[key] as? String { return oneLine(value) }
    }
    return ""
}

func oneLine(_ text: String, limit: Int = 160) -> String {
    let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        .trimmingCharacters(in: .whitespaces)
    return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
}

/// Lines in a piece of text, not counting a final newline.
func lineCount(_ text: String) -> Int {
    text.split(separator: "\n", omittingEmptySubsequences: false).count - (text.hasSuffix("\n") ? 1 : 0)
}
