import Foundation

/// A reply, split into the pieces a bubble draws differently.
///
/// docs/09-ui-spec.md: "Text | Markdown. Code blocks with syntax highlighting and a copy button".
/// Replies were rendered with a plain `Text`, so every list, bold run and fence arrived as its own
/// punctuation — and a model emits those constantly.
///
/// Splitting here rather than in the view because it is the part with rules, and one of those rules
/// only shows up while streaming: a fence that has been opened and not yet closed is a code block
/// whose last line has not arrived, not prose that happens to start with backticks. Getting that
/// wrong makes every reply containing code flicker between two layouts as it types.
public enum MessageMarkdown: Sendable {
    public enum Block: Equatable, Sendable, Identifiable {
        case prose(String)
        /// `language` is what followed the opening fence, if anything.
        case code(String, language: String?)
        /// `#`, `##`, `###`.
        case heading(String, level: Int)
        /// Consecutive `-`/`*`/`•` items, or `1.`/`1)` items.
        case list([String], ordered: Bool)

        public var id: String {
            switch self {
            case .prose(let text): "p:\(text.hashValue)"
            case .code(let text, let language): "c:\(language ?? "")\(text.hashValue)"
            case .heading(let text, let level): "h:\(level)\(text.hashValue)"
            case .list(let items, let ordered): "l:\(ordered)\(items.hashValue)"
            }
        }
    }

    public static func blocks(of text: String) -> [Block] {
        var blocks: [Block] = []
        var prose: [String] = []
        var items: [String] = []
        var ordered = false
        var code: [String] = []
        var language: String?
        var inCode = false

        func flushProse() {
            let joined = prose.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(.prose(joined)) }
            prose = []
        }
        func flushList() {
            if !items.isEmpty { blocks.append(.list(items, ordered: ordered)) }
            items = []
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(code.joined(separator: "\n"), language: language))
                    code = []
                    language = nil
                    inCode = false
                } else {
                    flushProse()
                    flushList()
                    let tag = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    language = tag.isEmpty ? nil : tag
                    inCode = true
                }
                continue
            }
            if inCode {
                code.append(line)
                continue
            }
            if let heading = line.wholeMatch(of: /(#{1,3}) +(.+)/) {
                flushProse()
                flushList()
                blocks.append(.heading(String(heading.2), level: heading.1.count))
                continue
            }
            if let item = listItem(line) {
                flushProse()
                if !items.isEmpty && item.ordered != ordered { flushList() }
                ordered = item.ordered
                items.append(item.text)
                continue
            }
            if !items.isEmpty {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    flushList()
                    continue
                }
                // An indented line continues the item above it.
                if line.hasPrefix("  ") || line.hasPrefix("\t") {
                    items[items.count - 1] += " " + trimmed
                    continue
                }
                flushList()
            }
            prose.append(line)
        }

        /*
         * Whatever is still open when the text runs out.
         *
         * While a reply streams, the closing fence has simply not arrived yet. Treating the tail as
         * prose until it does would redraw the whole block the moment it lands, so an unterminated
         * fence is code from the first line.
         */
        if inCode {
            blocks.append(.code(code.joined(separator: "\n"), language: language))
        } else {
            flushProse()
            flushList()
        }
        return blocks
    }

    private static func listItem(_ line: String) -> (ordered: Bool, text: String)? {
        if let match = line.wholeMatch(of: /\s{0,3}[-*•] +(.+)/) { return (false, String(match.1)) }
        if let match = line.wholeMatch(of: /\s{0,3}\d+[.)] +(.+)/) { return (true, String(match.1)) }
        return nil
    }

    /// Inline markdown — bold, italic, code spans, links — for one prose block.
    ///
    /// Falls back to the plain string when it will not parse. A reply is not worth losing to a stray
    /// bracket, and half-typed markdown is the normal state of a streaming one.
    public static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
