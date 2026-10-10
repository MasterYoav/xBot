import AppKit
import SwiftUI
import UniformTypeIdentifiers
import XBotCore

/// Abilities: the connectors, plugins, skills and MCP servers the agents can use — after Claude's
/// Plugins page. Everything here is read from, and changed through, the agents' own CLIs.
struct AbilitiesView: View {
    let workspace: Workspace
    @State private var tab = AbilityKind.plugins
    @State private var query = ""
    @State private var browsing = false
    @State private var addingServer = false
    @State private var choosingSkill = false
    @State private var skillAgent = HarnessKind.claude
    @State private var removing: Ability?

    private var catalog: AbilityCatalog { workspace.abilities }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                tabs
                if !catalog.missingAgents.isEmpty, catalog.missingAgents.count < HarnessKind.allCases.count {
                    Text(String(localized: "\(catalog.missingAgents.map(\.displayName).formatted(.list(type: .and))) isn't installed, so its abilities aren't shown."))
                        .captionText().foregroundStyle(Palette.textTertiary)
                }
                list
            }
            .frame(maxWidth: Metrics.abilitiesWidth)
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .task { await catalog.refresh() }
        .sheet(isPresented: $browsing) { BrowseSheet(catalog: catalog) }
        .sheet(isPresented: $addingServer) { AddServerSheet(catalog: catalog, agents: workspace.availableHarnesses) }
        .fileImporter(isPresented: $choosingSkill, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            Task {
                await catalog.addSkill(from: url, for: skillAgent)
                if scoped { url.stopAccessingSecurityScopedResource() }
                tab = .skills
            }
        }
        .confirmationDialog(
            removing.map { String(localized: "Remove \($0.title)?") } ?? "",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { ability in
            Button(String(localized: "Remove"), role: .destructive) { Task { await catalog.remove(ability) } }
        } message: { ability in
            Text(removalMessage(ability))
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(String(localized: "Abilities")).heroText().foregroundStyle(Palette.textPrimary)
                Text(String(localized: "Connectors, plugins, skills and MCP servers your agents can use"))
                    .bodyText().foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            HStack(spacing: Space.s) {
                Button(String(localized: "Browse")) { browsing = true }
                    .buttonStyle(OutlineButtonStyle())
                Menu {
                    Button(String(localized: "MCP Server…")) { addingServer = true }
                    Menu(String(localized: "Skill Folder…")) {
                        ForEach(workspace.availableHarnesses, id: \.self) { agent in
                            Button(String(localized: "For \(agent.displayName)…")) { skillAgent = agent; choosingSkill = true }
                        }
                    }
                    Divider()
                    Button(String(localized: "Plugin from a Marketplace…")) { browsing = true }
                } label: {
                    HStack(spacing: Space.xs) {
                        Text(String(localized: "Add"))
                        Image(systemName: "chevron.down").imageScale(.small)
                    }
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(PrimaryButtonStyle())
                .fixedSize()
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: Space.xs) {
            ForEach(AbilityKind.allCases, id: \.self) { kind in
                Button { tab = kind } label: {
                    HStack(spacing: Space.xs) {
                        Text(kind.title).foregroundStyle(tab == kind ? Palette.textPrimary : Palette.textSecondary)
                        if catalog.loading.contains(kind) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text(verbatim: "\(catalog.list(kind).count)").foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .font(Typography.emphasis)
                    .padding(.horizontal, Space.m)
                    .frame(height: Metrics.chipHeight + Space.xs)
                    .background(tab == kind ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: Space.m)
            SearchField(text: $query, prompt: String(localized: "Search \(tab.title.lowercased())"))
                .frame(maxWidth: Metrics.searchWidth)
        }
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        let items = catalog.list(tab).filter { $0.matches(query) }
        if items.isEmpty {
            empty
        } else {
            LazyVStack(alignment: .leading, spacing: Space.xs) {
                ForEach(items) { ability in
                    AbilityRow(ability: ability, busy: catalog.busy.contains(ability.id),
                               toggle: { on in Task { await catalog.setEnabled(ability, on) } },
                               remove: { removing = ability })
                }
            }
            if tab == .connectors {
                Button(String(localized: "Manage connectors on claude.ai")) {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/connectors")!)
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var empty: some View {
        VStack(spacing: Space.s) {
            if catalog.loading.contains(tab) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Asking your agents…")).captionText().foregroundStyle(Palette.textTertiary)
            } else if !query.isEmpty {
                Text(String(localized: "Nothing matches “\(query)”.")).bodyText().foregroundStyle(Palette.textSecondary)
            } else {
                Image(systemName: tab.symbol).font(Typography.hero).foregroundStyle(Palette.textTertiary)
                Text(emptySentence).bodyText().foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                emptyAction
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
    }

    private var emptySentence: String {
        switch tab {
        case .connectors: String(localized: "No claude.ai connectors yet. Connect Gmail, GitHub and more on claude.ai, and they show up here.")
        case .plugins: String(localized: "No plugins installed.")
        case .skills: String(localized: "No skills yet.")
        case .mcps: String(localized: "No MCP servers yet.")
        }
    }

    @ViewBuilder
    private var emptyAction: some View {
        switch tab {
        case .connectors:
            Button(String(localized: "Open claude.ai")) { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/connectors")!) }
                .buttonStyle(PrimaryButtonStyle())
        case .plugins: Button(String(localized: "Browse plugins")) { browsing = true }.buttonStyle(PrimaryButtonStyle())
        case .mcps: Button(String(localized: "Add an MCP server")) { addingServer = true }.buttonStyle(PrimaryButtonStyle())
        case .skills: EmptyView()
        }
    }

    private func removalMessage(_ ability: Ability) -> String {
        switch ability.removal {
        case .trash: String(localized: "The skill's folder goes to the Trash.")
        case .claudePlugin, .codexPlugin: String(localized: "\(ability.agent.displayName) uninstalls it. You can install it again from Browse.")
        default: String(localized: "\(ability.agent.displayName) forgets this server. You can add it again.")
        }
    }
}

extension AbilityKind {
    var symbol: String {
        switch self {
        case .connectors: "link"
        case .plugins: "puzzlepiece.extension"
        case .skills: "sparkles"
        case .mcps: "server.rack"
        }
    }
}

// MARK: - Row

private struct AbilityRow: View {
    let ability: Ability
    let busy: Bool
    let toggle: (Bool) -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Space.m) {
            AbilityIcon(ability: ability)
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.s) {
                    Text(ability.title).font(Typography.title).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    if let source = ability.source {
                        Text(source).bodyText().foregroundStyle(Palette.textTertiary).lineLimit(1)
                    }
                }
                if let summary = ability.summary, !summary.isEmpty {
                    Text(summary).bodyText().foregroundStyle(Palette.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: Space.m)
            HStack(spacing: Space.xs) {
                Circle().fill(Palette.agent(ability.agent)).frame(width: Metrics.dot, height: Metrics.dot)
                Text(ability.agent.displayName).captionText().foregroundStyle(Palette.textTertiary)
            }
            .help(String(localized: "Used by \(ability.agent.displayName)"))
            if ability.removal != nil || ability.location != nil {
                Menu {
                    if let location = ability.location {
                        Button(String(localized: "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([location]) }
                    }
                    if ability.removal != nil {
                        Divider()
                        Button(String(localized: "Remove…"), role: .destructive, action: remove)
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Palette.textSecondary)
                        .frame(width: Metrics.iconButton, height: Metrics.iconButton)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .accessibilityLabel(String(localized: "More for \(ability.title)"))
            }
            trailing
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.m)
        .background(hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var trailing: some View {
        if busy {
            ProgressView().controlSize(.small).frame(width: Metrics.toggleWidth)
        } else if let enabled = ability.enabled, ability.toggle != nil {
            Toggle(isOn: Binding(get: { enabled }, set: toggle)) { EmptyView() }
                .toggleStyle(.switch)
                .tint(Palette.accent)
                .labelsHidden()
                .accessibilityLabel(ability.title)
                .frame(width: Metrics.toggleWidth)
        } else if let status = ability.status {
            StatusPill(status.pill, status.text).frame(minWidth: Metrics.toggleWidth)
        } else if let enabled = ability.enabled {
            Text(enabled ? String(localized: "On") : String(localized: "Off"))
                .captionText().foregroundStyle(Palette.textTertiary)
                .frame(width: Metrics.toggleWidth)
                .help(ability.fixedReason ?? "")
        } else {
            Image(systemName: "lock").foregroundStyle(Palette.textTertiary)
                .frame(width: Metrics.toggleWidth)
                .help(ability.fixedReason ?? "")
        }
    }
}

extension Ability.Status {
    var pill: PillState {
        switch self {
        case .connected: .success
        case .needsSignIn: .warning
        case .failed: .failure
        case .pending: .neutral
        }
    }

    var text: String {
        switch self {
        case .connected: String(localized: "Connected")
        case .needsSignIn: String(localized: "Sign in")
        case .failed: String(localized: "Failed")
        case .pending: String(localized: "Pending")
        }
    }
}

/// The item's own icon when it ships one, else its kind's symbol, on a tile like the reference's.
private struct AbilityIcon: View {
    let ability: Ability

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Palette.raised)
            if let url = ability.icon, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(Space.s)
            } else {
                Image(systemName: ability.kind.symbol).font(Typography.title).foregroundStyle(Palette.agent(ability.agent))
            }
        }
        .frame(width: Metrics.abilityIcon, height: Metrics.abilityIcon)
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(Palette.hairline))
    }
}

// MARK: - Shared bits

struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.textTertiary)
            TextField(prompt, text: $text).textFieldStyle(.plain).bodyText()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textTertiary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Clear search"))
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: Metrics.chipHeight + Space.s)
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(Palette.hairline))
    }
}

/// The reference's "Browse directory": a bordered capsule.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.chip)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Space.m)
            .frame(height: Metrics.chipHeight)
            .overlay(Capsule().strokeBorder(Palette.hairline))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.1, bounce: 0), value: configuration.isPressed)
    }
}

// MARK: - Browse

private struct BrowseSheet: View {
    let catalog: AbilityCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var agent: HarnessKind?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text(String(localized: "Browse plugins")).titleText()
                Spacer()
                Button(String(localized: "Done")) { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
            HStack(spacing: Space.m) {
                Picker(String(localized: "Agent"), selection: $agent) {
                    Text(String(localized: "All")).tag(HarnessKind?.none)
                    ForEach(HarnessKind.allCases, id: \.self) { Text($0.displayName).tag(HarnessKind?.some($0)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                SearchField(text: $query, prompt: String(localized: "Search marketplaces"))
            }
            if catalog.isLoadingMarketplace && catalog.marketplace.isEmpty {
                VStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Reading the marketplaces…")).captionText().foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let shown = filtered
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(shown.prefix(300)) { plugin in row(plugin) }
                        if shown.count > 300 {
                            Text(String(localized: "\(shown.count - 300) more — search to narrow it down."))
                                .captionText().foregroundStyle(Palette.textTertiary).padding(Space.m)
                        }
                    }
                }
            }
        }
        .padding(Space.xl)
        .frame(width: Metrics.sheetWidth, height: Metrics.sheetHeight)
        .task { if catalog.marketplace.isEmpty { await catalog.loadMarketplace() } }
    }

    private var filtered: [MarketplacePlugin] {
        catalog.marketplace.filter { plugin in
            (agent == nil || plugin.agent == agent)
                && (query.isEmpty || [plugin.name, plugin.pluginID, plugin.summary ?? ""].contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    private func row(_ plugin: MarketplacePlugin) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.s) {
                    Text(plugin.name).emphasisText().foregroundStyle(Palette.textPrimary)
                    Text(plugin.marketplace).captionText().foregroundStyle(Palette.textTertiary)
                    Circle().fill(Palette.agent(plugin.agent)).frame(width: Metrics.dot, height: Metrics.dot)
                        .help(plugin.agent.displayName)
                }
                if let summary = plugin.summary {
                    Text(summary).captionText().foregroundStyle(Palette.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: Space.m)
            if catalog.installing.contains(plugin.id) {
                ProgressView().controlSize(.small)
            } else if plugin.installed {
                Text(String(localized: "Installed")).captionText().foregroundStyle(Palette.textTertiary)
            } else {
                Button(String(localized: "Install")) { Task { await catalog.install(plugin) } }
                    .buttonStyle(OutlineButtonStyle())
            }
        }
        .padding(Space.s)
    }
}

// MARK: - Add an MCP server

private struct AddServerSheet: View {
    let catalog: AbilityCatalog
    let agents: [HarnessKind]
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var usesURL = false
    @State private var command = ""
    @State private var url = ""
    @State private var chosen: Set<HarnessKind> = []
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(String(localized: "Add an MCP server")).titleText()
            Form {
                TextField(String(localized: "Name"), text: $name, prompt: Text(verbatim: "sentry"))
                Picker(String(localized: "Connects by"), selection: $usesURL) {
                    Text(String(localized: "Command")).tag(false)
                    Text(String(localized: "URL")).tag(true)
                }
                .pickerStyle(.segmented)
                if usesURL {
                    TextField(String(localized: "URL"), text: $url, prompt: Text(verbatim: "https://mcp.example.com/mcp"))
                } else {
                    TextField(String(localized: "Command"), text: $command, prompt: Text(verbatim: "npx -y @modelcontextprotocol/server-filesystem ~/Documents"))
                }
                ForEach(agents, id: \.self) { agent in
                    Toggle(String(localized: "Add to \(agent.displayName)"), isOn: Binding(
                        get: { chosen.contains(agent) },
                        set: { if $0 { chosen.insert(agent) } else { chosen.remove(agent) } }
                    ))
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button {
                    adding = true
                    Task {
                        if await catalog.addMCP(server) { dismiss() }
                        adding = false
                    }
                } label: {
                    if adding { ProgressView().controlSize(.mini) } else { Text(String(localized: "Add")) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!ready || adding)
            }
        }
        .padding(Space.xl)
        .frame(width: Metrics.settingsWidth)
        .onAppear { chosen = Set(agents) }
    }

    private var words: [String] { command.split(whereSeparator: \.isWhitespace).map(String.init) }

    private var server: NewMCPServer {
        NewMCPServer(name: name, target: usesURL ? .url(url.trimmingCharacters(in: .whitespaces))
                                              : .command(words.first ?? "", arguments: Array(words.dropFirst())),
                     agents: chosen)
    }

    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !chosen.isEmpty
            && (usesURL ? URL(string: url)?.scheme?.hasPrefix("http") == true : !words.isEmpty)
    }
}
