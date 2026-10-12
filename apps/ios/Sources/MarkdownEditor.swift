import SwiftUI
import XBotMarkdown

/// A Markdown file shown as a document (headings, lists, quotes, code), edited in place: tap a
/// block to change it, with bold, italic and friends from the keyboard's bar. It's written back as
/// Markdown; blocks you didn't touch stay exactly as they were in the file.
struct MarkdownEditor: View {
    @Binding var document: MarkdownDocument
    /// Called when an edit is finished (a block left), to save.
    var committed: () -> Void = {}
    var editable = true

    @State private var editing: UUID?
    @State private var draft = AttributedString()
    @State private var selection = AttributedTextSelection()
    @State private var plain = ""
    /// The edited block's Markdown when editing began: unchanged means the file's text is kept.
    @State private var startedAs = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(document.blocks) { block in
                    row(block)
                        .id(block.id)
                }
                // Room to start a new paragraph at the end.
                Color.clear.frame(height: 120).contentShape(Rectangle())
                    .onTapGesture { if editable { appendParagraph() } }
                    .overlay(alignment: .topLeading) {
                        if document.blocks.isEmpty {
                            Text(String(localized: "Tap to start writing")).foregroundStyle(.tertiary).allowsHitTesting(false)
                        }
                    }
            }
            .padding(.horizontal, Glass.margin)
            .padding(.vertical, 12)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: focused) { _, now in if !now { commit() } }
        .onChange(of: draft) { _, _ in splitOnReturn() }
        .onDisappear { commit() }
        .toolbar {
            if editing != nil {
                ToolbarItemGroup(placement: .keyboard) { formatBar }
            }
        }
        .accessibilityIdentifier("markdown-document")
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ block: MarkdownDocument.Block) -> some View {
        if editing == block.id {
            editor(block)
        } else {
            rendered(block)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if editable { begin(block) } }
        }
    }

    @ViewBuilder
    private func rendered(_ block: MarkdownDocument.Block) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(Self.styled(InlineMarkdown.attributed(Self.unwrapped(block.text)), block.kind))
                .padding(.top, level <= 2 ? 10 : 4)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            Text(Self.styled(InlineMarkdown.attributed(Self.unwrapped(block.text)), block.kind))
        case .bullet(let indent, let checked):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let checked {
                    Button { toggleTask(block.id) } label: {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(checked ? Theme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!editable)
                    .accessibilityLabel(checked ? String(localized: "Done") : String(localized: "Not done"))
                } else {
                    Circle().fill(.secondary).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                }
                Text(Self.styled(InlineMarkdown.attributed(Self.unwrapped(block.text)), block.kind))
                    .strikethrough(checked == true, color: .secondary)
                    .foregroundStyle(checked == true ? .secondary : .primary)
            }
            .padding(.leading, CGFloat(indent / 2) * 18)
        case .numbered(let indent, let number):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
                Text(Self.styled(InlineMarkdown.attributed(Self.unwrapped(block.text)), block.kind))
            }
            .padding(.leading, CGFloat(indent / 2) * 18)
        case .quote:
            Text(Self.styled(InlineMarkdown.attributed(Self.unwrapped(block.text)), block.kind))
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Capsule().fill(Theme.accent.opacity(0.6)).frame(width: 3) }
        case .code(let language):
            VStack(alignment: .leading, spacing: 6) {
                if !language.isEmpty { Text(language).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(block.text.isEmpty ? " " : block.text).font(.system(size: 13, design: .monospaced)).fixedSize()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))
        case .rule:
            Divider().padding(.vertical, 6)
        case .raw:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.text).font(.system(size: 13, design: .monospaced)).fixedSize()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(.separator)))
        }
    }

    @ViewBuilder
    private func editor(_ block: MarkdownDocument.Block) -> some View {
        Group {
            if block.kind.isLiteral {
                TextField("", text: $plain, axis: .vertical)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))
            } else {
                TextEditor(text: $draft, selection: $selection)
                    .scrollDisabled(true)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 36)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, -5)
                    .padding(.leading, block.kind.isListItem ? 16 : 0)
                    .overlay(alignment: .topLeading) {
                        if block.kind.isListItem {
                            Circle().fill(.secondary).frame(width: 6, height: 6).padding(.top, 14)
                        }
                    }
            }
        }
        .focused($focused)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.07)))
        .padding(-6)
        .accessibilityIdentifier("markdown-editing")
    }

    // MARK: Editing

    private func begin(_ block: MarkdownDocument.Block) {
        commit()
        editing = block.id
        if block.kind.isLiteral {
            plain = block.text
        } else {
            let styled = Self.styled(InlineMarkdown.attributed(Self.unwrapped(block.text)), block.kind)
            startedAs = InlineMarkdown.markdown(styled)
            draft = styled
            selection = AttributedTextSelection(insertionPoint: draft.endIndex)
        }
        Task { @MainActor in
            for delay in [40, 120, 250] where !focused {
                try? await Task.sleep(for: .milliseconds(delay))
                focused = true
            }
        }
    }

    /// Puts the edit into the document; an emptied block goes away.
    private func commit() {
        guard let id = editing, let index = document.blocks.firstIndex(where: { $0.id == id }) else { editing = nil; return }
        editing = nil
        var block = document.blocks[index]
        if block.kind.isLiteral {
            block.text = plain
        } else {
            let markdown = InlineMarkdown.markdown(draft)
            if markdown != startedAs { block.text = markdown }
        }
        let emptied = block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && block.kind != .rule
            && { if case .code = block.kind { false } else { true } }()
        if emptied {
            document.blocks.remove(at: index)
        } else {
            document.blocks[index] = block
        }
        committed()
    }

    /// Return makes the next block: the next list item, or a new paragraph. Return on an empty
    /// list item ends the list.
    private func splitOnReturn() {
        guard let id = editing, let index = document.blocks.firstIndex(where: { $0.id == id }),
              let newline = draft.characters.firstIndex(of: "\n") else { return }
        let kind = document.blocks[index].kind
        let before = AttributedString(draft[draft.startIndex..<newline])
        let after = AttributedString(draft[draft.characters.index(after: newline)...])
        let beforeText = InlineMarkdown.markdown(before)

        if kind.isListItem, beforeText.trimmingCharacters(in: .whitespaces).isEmpty, after.characters.isEmpty {
            document.blocks[index].kind = .paragraph
            draft = Self.styled(AttributedString(), .paragraph)
            return
        }
        document.blocks[index].text = beforeText
        let nextKind: MarkdownDocument.Kind = switch kind {
        case .bullet(let indent, let checked): .bullet(indent: indent, checked: checked.map { _ in false })
        case .numbered(let indent, let number): .numbered(indent: indent, number: number + 1)
        case .quote: .quote
        default: .paragraph
        }
        let next = MarkdownDocument.Block(kind: nextKind, text: InlineMarkdown.markdown(after))
        document.blocks.insert(next, at: index + 1)
        editing = nil
        begin(next)
        selection = AttributedTextSelection(insertionPoint: draft.startIndex)
        committed()
    }

    private func appendParagraph() {
        if let last = document.blocks.last, editing == nil,
           last.kind == .paragraph, last.text.isEmpty { begin(last); return }
        let block = MarkdownDocument.Block(kind: .paragraph, text: "")
        document.blocks.append(block)
        begin(block)
    }

    private func toggleTask(_ id: UUID) {
        guard let index = document.blocks.firstIndex(where: { $0.id == id }),
              case .bullet(let indent, let checked?) = document.blocks[index].kind else { return }
        document.blocks[index].kind = .bullet(indent: indent, checked: !checked)
        committed()
    }

    // MARK: The keyboard's bar

    private var editingKind: MarkdownDocument.Kind? {
        editing.flatMap { id in document.blocks.first { $0.id == id }?.kind }
    }

    @ViewBuilder private var formatBar: some View {
        if let kind = editingKind, !kind.isLiteral {
            Menu {
                Button { setKind(.paragraph) } label: { Label(String(localized: "Text"), systemImage: "text.alignleft") }
                Button { setKind(.heading(level: 1)) } label: { Label(String(localized: "Title"), systemImage: "textformat.size.larger") }
                Button { setKind(.heading(level: 2)) } label: { Label(String(localized: "Heading"), systemImage: "textformat.size") }
                Button { setKind(.heading(level: 3)) } label: { Label(String(localized: "Subheading"), systemImage: "textformat.size.smaller") }
                Divider()
                Button { setKind(.bullet(indent: 0, checked: nil)) } label: { Label(String(localized: "Bulleted list"), systemImage: "list.bullet") }
                Button { setKind(.numbered(indent: 0, number: 1)) } label: { Label(String(localized: "Numbered list"), systemImage: "list.number") }
                Button { setKind(.bullet(indent: 0, checked: false)) } label: { Label(String(localized: "Checklist"), systemImage: "checklist") }
                Button { setKind(.quote) } label: { Label(String(localized: "Quote"), systemImage: "text.quote") }
            } label: { Image(systemName: "textformat") }
            .accessibilityLabel(String(localized: "Block style"))
            Button { toggle(.stronglyEmphasized) } label: { Image(systemName: "bold") }.accessibilityLabel(String(localized: "Bold"))
            Button { toggle(.emphasized) } label: { Image(systemName: "italic") }.accessibilityLabel(String(localized: "Italic"))
            Button { toggle(.strikethrough) } label: { Image(systemName: "strikethrough") }.accessibilityLabel(String(localized: "Strikethrough"))
            Button { toggle(.code) } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }.accessibilityLabel(String(localized: "Code"))
        }
        Spacer()
        Button(String(localized: "Done")) { focused = false }.fontWeight(.semibold)
    }

    private func setKind(_ kind: MarkdownDocument.Kind) {
        guard let id = editing, let index = document.blocks.firstIndex(where: { $0.id == id }) else { return }
        document.blocks[index].kind = kind
        // Same text, new look.
        draft = Self.restyled(draft, kind)
    }

    private func toggle(_ intent: InlinePresentationIntent) {
        guard let kind = editingKind, case .ranges(let ranges) = selection.indices(in: draft), !ranges.isEmpty else { return }
        let allHave = draft[ranges].runs.allSatisfy { ($0.inlinePresentationIntent ?? []).contains(intent) }
        draft.transformAttributes(in: &selection) { container in
            var intents = container.inlinePresentationIntent ?? []
            if allHave { intents.remove(intent) } else { intents.insert(intent) }
            container.inlinePresentationIntent = intents.isEmpty ? nil : intents
            container.font = Self.font(kind, intents)
            container.strikethroughStyle = intents.contains(.strikethrough) ? .single : nil
            container.backgroundColor = intents.contains(.code) ? Color(.tertiarySystemFill) : nil
        }
    }

    // MARK: Looks

    /// Soft line breaks read as spaces, as Markdown shows them.
    static func unwrapped(_ text: String) -> String { text.replacingOccurrences(of: "\n", with: " ") }

    static func font(_ kind: MarkdownDocument.Kind, _ intents: InlinePresentationIntent) -> Font {
        var font: Font = switch kind {
        case .heading(1): .system(size: 30, weight: .heavy, design: .rounded)
        case .heading(2): .system(size: 23, weight: .bold, design: .rounded)
        case .heading(3): .system(size: 19, weight: .bold, design: .rounded)
        case .heading: .system(size: 17, weight: .bold, design: .rounded)
        default: .system(size: 17, design: .default)
        }
        if intents.contains(.code) { font = .system(size: 15, design: .monospaced) }
        if intents.contains(.stronglyEmphasized) { font = font.bold() }
        if intents.contains(.emphasized) || kind == .quote { font = font.italic() }
        return font
    }

    /// Inline-styled text with the fonts and colours that show its styling (in Text and while editing).
    static func styled(_ text: AttributedString, _ kind: MarkdownDocument.Kind) -> AttributedString {
        restyled(text, kind)
    }

    static func restyled(_ text: AttributedString, _ kind: MarkdownDocument.Kind) -> AttributedString {
        var out = text
        if out.characters.isEmpty {
            out.font = font(kind, [])
            return out
        }
        for run in out.runs {
            let intents = run.inlinePresentationIntent ?? []
            out[run.range].font = font(kind, intents)
            out[run.range].strikethroughStyle = intents.contains(.strikethrough) ? .single : nil
            out[run.range].backgroundColor = intents.contains(.code) ? Color(.tertiarySystemFill) : nil
            if run.link != nil {
                out[run.range].foregroundColor = Theme.accent
                out[run.range].underlineStyle = .single
            } else if kind == .quote {
                out[run.range].foregroundColor = .secondary
            }
        }
        return out
    }
}
