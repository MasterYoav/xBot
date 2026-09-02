import SwiftUI
import XBotCore
import XBotEngine

/// ⌘K. Fuzzy search over name and label; ⏎ opens; the first row always creates.
///
/// The footer states the verbs, because a keyboard affordance nobody knows about does not exist.
public struct CommandPalette: View {
    @Environment(AppState.self) private var state
    @Binding private var isOpen: Bool

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    public init(isOpen: Binding<Bool>) {
        self._isOpen = isOpen
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // A scrim here, unlike the panel: this one IS modal — it takes the keyboard, and
            // dimming says so.
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { isOpen = false }

            VStack(spacing: 0) {
                TextField(String(localized: "Search or create agents"), text: $query)
                    .textFieldStyle(.plain)
                    .bodyText()
                    .focused($focused)
                    .padding(Space.m)
                    .onSubmit(commit)
                    .onChange(of: query) { highlighted = 0 }

                Divider().overlay(Palette.separator)

                createRow

                ForEach(Array(matches.enumerated()), id: \.element.id) { index, agent in
                    HStack(spacing: Space.s) {
                        AgentAvatar(agent: agent, size: .small)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(agent.name).bodyText()
                            Text(agent.label)
                                .captionText()
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if index < 8 {
                            Text("⌘\(index + 2)")
                                .captionText()
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(index + 1 == highlighted ? Palette.elevatedSurface : .clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        highlighted = index + 1
                        commit()
                    }
                }

                Divider().overlay(Palette.separator)

                HStack {
                    Spacer()
                    Text(String(localized: "⏎ open"))
                        .captionText()
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
            }
            .frame(width: 460)
            .background(
                Palette.elevatedSurface,
                in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
            )
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .padding(.top, 120)
        }
        .onAppear { focused = true }
        .onExitCommand { isOpen = false }
    }

    private var createRow: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 22, height: 22)
            Text(createTitle).bodyText()
            Spacer()
            Text("⌘1")
                .captionText()
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background(highlighted == 0 ? Palette.elevatedSurface : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            highlighted = 0
            commit()
        }
    }

    private var createTitle: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "Create new agent")
        }
        return String(localized: "Create “\(trimmed)”")
    }

    private var matches: [Agent] {
        guard !query.isEmpty else { return state.agents }
        let needle = query.lowercased()
        return state.agents.filter {
            $0.name.lowercased().contains(needle) || $0.label.lowercased().contains(needle)
        }
    }

    private func commit() {
        if highlighted == 0 {
            state.createAgent(named: query)
        } else {
            let index = highlighted - 1
            guard index < matches.count else { return }
            state.select(matches[index].id)
        }
        isOpen = false
    }
}
