import Foundation

/// A Markdown file as blocks you can edit one at a time (headings, paragraphs, list items, quotes,
/// code, rules), written back as Markdown. Blocks you didn't touch are written back exactly as they
/// were, spacing and all; only edited ones are re-written from their text.
public struct MarkdownDocument: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case heading(level: Int)
        case paragraph
        /// `checked` is nil for a plain bullet, true/false for a task.
        case bullet(indent: Int, checked: Bool?)
        case numbered(indent: Int, number: Int)
        case quote
        /// `text` is the code itself, edited as plain text.
        case code(language: String)
        case rule
        /// Anything shown and edited as-is (tables, HTML): `text` is the source.
        case raw

        public var isListItem: Bool {
            switch self { case .bullet, .numbered: true; default: false }
        }

        /// Plain-text blocks: no inline styling.
        public var isLiteral: Bool {
            switch self { case .code, .raw, .rule: true; default: false }
        }
    }

    public struct Block: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var kind: Kind
        /// Inline Markdown for text blocks; the literal content for code and raw blocks.
        public var text: String
        /// The blank lines (and anything else) before it, kept as they were.
        var gap: String
        /// What it was in the file, written back while the block is unchanged.
        var source: String?
        var original: (kind: Kind, text: String)?

        public init(kind: Kind, text: String) {
            self.init(id: UUID(), kind: kind, text: text, gap: "", source: nil)
        }

        init(id: UUID = UUID(), kind: Kind, text: String, gap: String, source: String?) {
            self.id = id
            self.kind = kind
            self.text = text
            self.gap = gap
            self.source = source
            original = source == nil ? nil : (kind, text)
        }

        var isUnchanged: Bool { original.map { $0.kind == kind && $0.text == text } ?? false }

        public static func == (a: Block, b: Block) -> Bool {
            a.id == b.id && a.kind == b.kind && a.text == b.text && a.gap == b.gap && a.source == b.source
        }
    }

    public var blocks: [Block]
    /// Whatever followed the last block (usually a newline).
    var trailing: String

    public init(blocks: [Block]) {
        self.blocks = blocks
        trailing = "\n"
    }

    // MARK: Writing

    /// The document as Markdown: untouched blocks verbatim, edited ones re-written.
    public var markdown: String {
        var out = ""
        for (index, block) in blocks.enumerated() {
            let gap: String
            if block.source != nil, index == 0 || !block.gap.isEmpty {
                gap = index == 0 ? "" : block.gap
            } else if index == 0 {
                gap = ""
            } else {
                // New blocks: list items stay in their list, everything else gets a blank line.
                gap = block.kind.isListItem && blocks[index - 1].kind.isListItem ? "\n" : "\n\n"
            }
            out += gap
            out += block.isUnchanged ? block.source ?? Self.render(block) : Self.render(block)
        }
        return out + (blocks.isEmpty ? "" : trailing)
    }

    static func render(_ block: Block) -> String {
        switch block.kind {
        case .heading(let level):
            return String(repeating: "#", count: min(max(level, 1), 6)) + " " + block.text.replacingOccurrences(of: "\n", with: " ")
        case .paragraph:
            return block.text
        case .bullet(let indent, let checked):
            let box = checked.map { $0 ? "[x] " : "[ ] " } ?? ""
            return item(indent: indent, marker: "- " + box, text: block.text)
        case .numbered(let indent, let number):
            return item(indent: indent, marker: "\(number). ", text: block.text)
        case .quote:
            return block.text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
        case .code(let language):
            let fence = block.text.contains("```") ? "~~~~" : "```"
            return fence + language + "\n" + block.text + "\n" + fence
        case .rule:
            return "---"
        case .raw:
            return block.text
        }
    }

    private static func item(indent: Int, marker: String, text: String) -> String {
        let pad = String(repeating: " ", count: indent)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let rest = lines.dropFirst().map { pad + String(repeating: " ", count: marker.count) + $0 }
        return ([pad + marker + (lines.first.map(String.init) ?? "")] + rest).joined(separator: "\n")
    }

    // MARK: Reading

    public init(parsing markdown: String) {
        var lines = markdown.components(separatedBy: "\n")
        // The file's final newline (and any blank lines after the last block) are kept apart.
        var trailing = ""
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty, lines.count > 1 {
            trailing = "\n" + trailing
            lines.removeLast()
        }
        if lines == [""] { lines = [] }
        self.trailing = trailing.isEmpty ? "" : trailing
        blocks = []

        var index = 0
        var gap = ""
        func add(_ kind: Kind, _ text: String, _ from: Int, _ to: Int) {
            let source = lines[from..<to].joined(separator: "\n")
            blocks.append(Block(kind: kind, text: text, gap: gap, source: source))
            gap = "\n"
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                gap += "\n"
                index += 1
                continue
            }
            let start = index

            // Fenced code.
            if let fence = Self.fence(line) {
                var body: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence.marker) {
                    body.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                add(.code(language: fence.language), body.joined(separator: "\n"), start, index)
                continue
            }
            // ATX heading.
            if let match = line.firstMatch(of: /^ {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*#*[ \t]*$/) {
                add(.heading(level: match.1.count), String(match.2 ?? ""), start, index + 1)
                index += 1
                continue
            }
            // Thematic break.
            if line.wholeMatch(of: /^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$/) != nil {
                add(.rule, "", start, index + 1)
                index += 1
                continue
            }
            // Tables and HTML: kept as they are.
            if trimmed.hasPrefix("|") || trimmed.hasPrefix("<") {
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
                add(.raw, lines[start..<index].joined(separator: "\n"), start, index)
                continue
            }
            // Quote.
            if trimmed.hasPrefix(">") {
                var body: [String] = []
                while index < lines.count, let m = lines[index].wholeMatch(of: /^ {0,3}> ?(.*)$/) {
                    body.append(String(m.1))
                    index += 1
                }
                add(.quote, body.joined(separator: "\n"), start, index)
                continue
            }
            // List item, with its continuation lines.
            if let item = Self.listItem(line) {
                var body = [item.text]
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                    guard !nextTrimmed.isEmpty, Self.listItem(next) == nil, Self.fence(next) == nil,
                          next.hasPrefix(" ") || next.hasPrefix("\t") else { break }
                    body.append(nextTrimmed)
                    index += 1
                }
                add(item.kind, body.joined(separator: "\n"), start, index)
                continue
            }
            // Paragraph (a setext underline makes it a heading).
            var body = [line]
            index += 1
            var kind = Kind.paragraph
            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty { break }
                if next.wholeMatch(of: /^ {0,3}=+[ \t]*$/) != nil { kind = .heading(level: 1); index += 1; break }
                if next.wholeMatch(of: /^ {0,3}-+[ \t]*$/) != nil { kind = .heading(level: 2); index += 1; break }
                if Self.fence(next) != nil || Self.listItem(next) != nil || nextTrimmed.hasPrefix("#") || nextTrimmed.hasPrefix(">") { break }
                body.append(next)
                index += 1
            }
            let text = kind == .paragraph ? body.joined(separator: "\n") : body.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            add(kind, text, start, index)
        }
        // Blank lines after the last block that weren't at the very end of the file.
        if !gap.isEmpty, gap != "\n", !blocks.isEmpty { self.trailing = String(gap.dropFirst()) + self.trailing }
    }

    private static func fence(_ line: String) -> (marker: String, language: String)? {
        guard let m = line.wholeMatch(of: /^ {0,3}(`{3,}|~{3,})[ \t]*([^`]*?)[ \t]*$/) else { return nil }
        return (String(m.1), String(m.2))
    }

    private static func listItem(_ line: String) -> (kind: Kind, text: String)? {
        if let m = line.wholeMatch(of: /^([ \t]*)[-*+][ \t]+(?:\[([ xX])\][ \t]+)?(.*)$/) {
            let checked: Bool? = m.2.map { $0 != " " }
            return (.bullet(indent: m.1.count, checked: checked), String(m.3))
        }
        if let m = line.wholeMatch(of: /^([ \t]*)(\d{1,9})[.)][ \t]+(.*)$/) {
            return (.numbered(indent: m.1.count, number: Int(m.2) ?? 1), String(m.3))
        }
        return nil
    }
}

/// Inline Markdown (bold, italic, code, strikethrough, links) to styled text and back.
public enum InlineMarkdown {
    public static func attributed(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }

    /// Styled text back to Markdown: only the styles above are kept; anything else is plain text.
    public static func markdown(_ text: AttributedString) -> String {
        struct Style: Equatable {
            var link: URL?
            var strong = false
            var emphasis = false
            var strike = false
            var code = false
        }
        var out = ""
        var open: [String] = []   // markers opened, innermost last
        var current = Style()

        func close(_ marker: String) {
            // A closing marker can't follow a space: put it before any trailing spaces.
            let spaces = out.reversed().prefix { $0 == " " || $0 == "\t" }.count
            let tail = String(out.suffix(spaces))
            out.removeLast(spaces)
            out += marker + tail
        }

        func closeAll(down to: Int) {
            while open.count > to {
                let marker = open.removeLast()
                close(marker.hasPrefix("[") ? "](\(current.link?.absoluteString ?? ""))" : marker)
            }
        }

        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            let style = Style(link: run.link, strong: intent.contains(.stronglyEmphasized), emphasis: intent.contains(.emphasized),
                              strike: intent.contains(.strikethrough), code: intent.contains(.code))
            var piece = String(text[run.range].characters)
            if style != current {
                closeAll(down: 0)
                current = style
                // Leading spaces go before the opening markers.
                let lead = piece.prefix { $0 == " " || $0 == "\t" }
                out += lead
                piece.removeFirst(lead.count)
                if style.link != nil { open.append("["); out += "[" }
                if style.strong { open.append("**"); out += "**" }
                if style.emphasis { open.append("*"); out += "*" }
                if style.strike { open.append("~~"); out += "~~" }
                if style.code { open.append("`"); out += "`" }
            }
            out += style.code ? piece : escape(piece)
        }
        closeAll(down: 0)
        return out
    }

    /// Characters that would otherwise start styling.
    private static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            if "*`[]\\".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }
}
