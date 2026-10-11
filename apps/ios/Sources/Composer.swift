import SwiftUI
import XBotRemote

/// The bottom bar: the message field, Send / Stop, and the same chips as on the Mac.
struct Composer: View {
    let client: RemoteClient
    let chat: RemoteChat
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    @State private var sending = false

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending && chat.blocked == nil
            && (client.link == .local || client.link == .cloud)
    }

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    agentMenu
                    modeMenu
                    effortMenu
                    planChip
                }
                .padding(.horizontal, 16)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(chat.blocked ?? String(localized: "Message \(chat.crewName ?? chat.agentName)"), text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused(focused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemBackground)))
                    .disabled(chat.blocked != nil)
                    .accessibilityIdentifier("composer")
                if chat.isRunning {
                    Button { Task { await client.stop(chat.id) } } label: {
                        Image(systemName: "stop.fill").font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40)
                            .background(Circle().fill(.primary)).foregroundStyle(Color(.systemBackground))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Stop"))
                    .keyboardShortcut(.escape, modifiers: [])
                } else {
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.accent.opacity(canSend ? 1 : 0.3))).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel(String(localized: "Send"))
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func send() async {
        let message = text
        sending = true
        text = ""
        let answer = await client.send(message, in: chat.id)
        if !answer.ok { text = message }
        sending = false
    }

    // MARK: Chips

    private var agent: RemoteAgent? { client.agent(chat.agent) }

    private var agentMenu: some View {
        Menu {
            ForEach(client.agents) { agent in
                Menu(agent.name) {
                    Button(String(localized: "Default model")) {
                        Task { await client.set(RemoteChatSettings(agent: agent.id, model: Choice(nil)), for: chat.id) }
                    }
                    ForEach(agent.models) { model in
                        Button(model.name) { Task { await client.set(RemoteChatSettings(agent: agent.id, model: Choice(model.id)), for: chat.id) } }
                    }
                }
            }
        } label: {
            Chip(text: [chat.agentName, chat.model.map { id in agent?.models.first { $0.id == id }?.name ?? id }].compactMap { $0 }.joined(separator: " · "),
                 dot: Theme.agentColor(chat.agent))
        }
        .disabled(chat.isRunning)
    }

    private var modeMenu: some View {
        Menu {
            ForEach([("readOnly", String(localized: "Read only"), "eye"), ("editFiles", String(localized: "Can edit"), "pencil"),
                     ("fullAccess", String(localized: "Full access"), "bolt")], id: \.0) { mode in
                Button { Task { await client.set(RemoteChatSettings(mode: mode.0), for: chat.id) } } label: { Label(mode.1, systemImage: mode.2) }
            }
            if agent?.editingNeedsFullAccess == true {
                Text(String(localized: "\(chat.agentName) can only edit with full access."))
            }
        } label: {
            Chip(text: modeTitle, symbol: modeSymbol)
        }
        .disabled(chat.isRunning)
    }

    private var modeTitle: String {
        switch chat.mode {
        case "readOnly": String(localized: "Read only")
        case "fullAccess": String(localized: "Full access")
        default: String(localized: "Can edit")
        }
    }

    private var modeSymbol: String {
        switch chat.mode { case "readOnly": "eye"; case "fullAccess": "bolt"; default: "pencil" }
    }

    private var efforts: [String] {
        let model = chat.model.flatMap { id in agent?.models.first { $0.id == id } } ?? agent?.models.first
        let listed = model?.efforts ?? []
        return listed.isEmpty ? ["low", "medium", "high"] : listed
    }

    private var effortMenu: some View {
        Menu {
            Button(String(localized: "The agent's default")) { Task { await client.set(RemoteChatSettings(effort: Choice(nil)), for: chat.id) } }
            ForEach(efforts, id: \.self) { effort in
                Button(effort.capitalized) { Task { await client.set(RemoteChatSettings(effort: Choice(effort)), for: chat.id) } }
            }
        } label: {
            Chip(text: chat.effort?.capitalized ?? String(localized: "Reasoning"), symbol: "brain")
        }
        .disabled(chat.isRunning)
    }

    @ViewBuilder private var planChip: some View {
        let makesPlans = agent?.makesPlans ?? true
        Button {
            Task { await client.set(RemoteChatSettings(planMode: !chat.planMode), for: chat.id) }
        } label: {
            Chip(text: String(localized: "Plan"), symbol: "list.bullet.clipboard", on: chat.planMode)
        }
        .disabled(!makesPlans || chat.isRunning)
        .opacity(makesPlans ? 1 : 0.4)
    }
}

/// Settings shared by a new chat's sheet.
struct ComposerSettings {
    var agent: String?
    var model: String?
    var mode = "editFiles"
    var planMode = false

    var remote: RemoteChatSettings {
        RemoteChatSettings(agent: agent, model: Choice(model), mode: mode, planMode: planMode)
    }
}

struct ComposerSettingsRows: View {
    let client: RemoteClient
    @Binding var settings: ComposerSettings

    var body: some View {
        Picker(String(localized: "Agent"), selection: $settings.agent) {
            ForEach(client.agents) { Text($0.name).tag(String?.some($0.id)) }
        }
        .onChange(of: settings.agent) { settings.model = nil }
        if let agent = settings.agent.flatMap(client.agent), !agent.models.isEmpty {
            Picker(String(localized: "Model"), selection: $settings.model) {
                Text(String(localized: "Default")).tag(String?.none)
                ForEach(agent.models) { Text($0.name).tag(String?.some($0.id)) }
            }
        }
        Picker(String(localized: "Permissions"), selection: $settings.mode) {
            Text(String(localized: "Read only")).tag("readOnly")
            Text(String(localized: "Can edit")).tag("editFiles")
            Text(String(localized: "Full access")).tag("fullAccess")
        }
        if settings.agent.flatMap(client.agent)?.makesPlans != false {
            Toggle(String(localized: "Plan first"), isOn: $settings.planMode)
        }
    }
}

struct Chip: View {
    let text: String
    var symbol: String?
    var dot: Color?
    var on = false

    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            if let symbol { Image(systemName: symbol).font(.caption) }
            Text(text).font(.footnote.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(on ? Theme.accent.opacity(0.18) : Color(.secondarySystemBackground)))
        .foregroundStyle(on ? Theme.accent : .primary)
    }
}
