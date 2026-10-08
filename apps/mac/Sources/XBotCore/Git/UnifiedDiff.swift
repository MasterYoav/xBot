import Foundation

public struct DiffLine: Equatable, Sendable, Identifiable {
    public enum Kind: Sendable { case hunk, context, added, removed }

    public var id: Int
    public var kind: Kind
    public var old: Int?
    public var new: Int?
    public var text: String

    public init(id: Int, kind: Kind, old: Int? = nil, new: Int? = nil, text: String) {
        self.id = id
        self.kind = kind
        self.old = old
        self.new = new
        self.text = text
    }
}

/// A unified diff as numbered lines. The headers before the first hunk are dropped.
public enum UnifiedDiff {
    public static func parse(_ text: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        var old = 0, new = 0, inHunk = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("@@") {
                // "@@ -3,3 +3,4 @@ context": where each side's lines start.
                inHunk = true
                let fields = line.split(separator: " ")
                func start(_ i: Int) -> Int {
                    fields.count > i ? Int(fields[i].dropFirst().split(separator: ",").first ?? "") ?? 0 : 0
                }
                old = start(1)
                new = start(2)
                lines.append(DiffLine(id: lines.count, kind: .hunk, text: line))
                continue
            }
            guard inHunk, let first = line.first else { continue }
            let body = String(line.dropFirst())
            switch first {
            case " ":
                lines.append(DiffLine(id: lines.count, kind: .context, old: old, new: new, text: body))
                old += 1
                new += 1
            case "-":
                lines.append(DiffLine(id: lines.count, kind: .removed, old: old, text: body))
                old += 1
            case "+":
                lines.append(DiffLine(id: lines.count, kind: .added, new: new, text: body))
                new += 1
            default:
                break  // "\ No newline at end of file"
            }
        }
        return lines
    }
}
