import SwiftUI
import XBotCore
import XBotEngine

/// What this agent may reach — connected plugins, grant toggles, and a path to full setup.
public struct AgentReachSection: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    @State private var isExpanded = true
    @State private var expandedServers: Set<String> = []

    public init() {}

    public var body: some View {
        CollapsibleSettingsSection(
            title: String(localized: "What it can reach"),
            isExpanded: $isExpanded
        ) {
            content
        }
        .task(id: state.selectedAgentID) {
            await state.refreshAgentSettingsData()
            if let first = state.pluginsPage?.servers.first?.id {
                expandedServers.insert(first)
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                await state.refreshPluginsData()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.pluginsPageLoading, state.pluginsPage == nil {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let page = state.pluginsPage {
            connectedSection(page)
            skillsSection(page)
            exploreSection(page)
        } else {
            Text(String(localized: "Could not load plugins."))
                .captionText()
                .foregroundStyle(Palette.textSecondary)
        }

        Button(String(localized: "Manage plugins…")) {
            state.preparePluginsAdmin()
            openWindow(id: "plugins-admin")
        }
        .buttonStyle(XBotButtonStyle())
        .padding(.top, Space.xs)
    }

    @ViewBuilder
    private func connectedSection(_ page: PluginsPage) -> some View {
        if page.servers.isEmpty {
            Text(String(localized: "No plugins connected for this deployment yet."))
                .captionText()
                .foregroundStyle(Palette.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(page.servers) { server in
                    serverBlock(server)
                }
            }
        }
    }

    @ViewBuilder
    private func serverBlock(_ server: PluginServer) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button {
                withAnimation(Motion.quick) {
                    toggleServer(server.id)
                }
            } label: {
                HStack {
                    pluginMark(for: server.id)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(server.title).bodyEmphasis()
                        Text(serverSummary(server))
                            .captionText()
                            .foregroundStyle(
                                server.lastError == nil ? Palette.textTertiary : Palette.stateFailed
                            )
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .rotationEffect(.degrees(expandedServers.contains(server.id) ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            if expandedServers.contains(server.id) {
                if server.tools.isEmpty {
                    Text(String(localized: "No tools listed yet."))
                        .captionText()
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.leading, Space.l)
                } else {
                    VStack(alignment: .leading, spacing: Space.s) {
                        ForEach(server.tools) { tool in
                            toolToggle(tool)
                        }
                    }
                    .padding(.leading, Space.l)
                }

                Button(String(localized: "Configure…")) {
                    state.preparePluginsAdmin(path: "admin/plugins/\(server.id)")
                    openWindow(id: "plugins-admin")
                }
                .buttonStyle(XBotButtonStyle())
                .padding(.leading, Space.l)
                .padding(.top, Space.xxs)
            }
        }
    }

    @ViewBuilder
    private func skillsSection(_ page: PluginsPage) -> some View {
        if !page.skills.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(String(localized: "Skills"))
                    .captionText()
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, Space.s)
                ForEach(page.skills) { skill in
                    skillToggle(skill)
                }
            }
        }
    }

    @ViewBuilder
    private func exploreSection(_ page: PluginsPage) -> some View {
        let connected = Set(page.servers.map(\.id))
        let explore = page.catalogue.filter { !connected.contains($0.key) }
        if !explore.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(String(localized: "Explore"))
                    .captionText()
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, Space.s)
                ForEach(explore) { item in
                    HStack(spacing: Space.s) {
                        pluginMark(for: item.key)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title).bodyText()
                            Text(item.summary)
                                .captionText()
                                .foregroundStyle(Palette.textTertiary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button(String(localized: "Set up")) {
                            state.preparePluginsAdmin(path: "admin/plugins/\(item.key)")
                            openWindow(id: "plugins-admin")
                        }
                        .buttonStyle(XBotButtonStyle())
                    }
                }
            }
        }
    }

    private func toolToggle(_ tool: PluginTool) -> some View {
        Toggle(isOn: toolBinding(tool)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tool.name).bodyText()
                HStack(spacing: Space.xxs) {
                    Text(tool.effect == .read ? String(localized: "Read") : String(localized: "Write"))
                        .captionText()
                        .foregroundStyle(Palette.textTertiary)
                    if !tool.summary.isEmpty {
                        Text("·")
                            .captionText()
                            .foregroundStyle(Palette.textTertiary)
                        Text(tool.summary)
                            .captionText()
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func skillToggle(_ skill: PluginSkill) -> some View {
        Toggle(isOn: skillBinding(skill)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(skill.title).bodyText()
                if !skill.summary.isEmpty {
                    Text(skill.summary)
                        .captionText()
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func toolBinding(_ tool: PluginTool) -> Binding<Bool> {
        Binding(
            get: { isGranted(to: tool.grantedTo) },
            set: { enabled in
                Task { await state.setPluginGrant(kind: .mcp, ref: tool.ref, enabled: enabled) }
            }
        )
    }

    private func skillBinding(_ skill: PluginSkill) -> Binding<Bool> {
        Binding(
            get: { isGranted(to: skill.grantedTo) },
            set: { enabled in
                Task { await state.setPluginGrant(kind: .skill, ref: skill.slug, enabled: enabled) }
            }
        )
    }

    private func isGranted(to agents: [Agent.ID]) -> Bool {
        guard let selected = state.selectedAgentID else { return false }
        return agents.contains(selected)
    }

    private func serverSummary(_ server: PluginServer) -> String {
        if let error = server.lastError { return error }
        let granted = server.tools.filter { isGranted(to: $0.grantedTo) }.count
        if server.tools.isEmpty { return String(localized: "No tools yet") }
        if granted == 0 { return String(localized: "No tools granted to this agent") }
        return String(localized: "\(granted) of \(server.tools.count) tools granted")
    }

    private func toggleServer(_ id: String) {
        if expandedServers.contains(id) {
            expandedServers.remove(id)
        } else {
            expandedServers.insert(id)
        }
    }

    @ViewBuilder
    private func pluginMark(for key: String) -> some View {
        let symbol = switch key {
        case "google-drive": "externaldrive"
        case "notion": "doc.text"
        default: "puzzlepiece.extension"
        }
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(Palette.textSecondary)
            .frame(width: 20, alignment: .center)
    }
}
