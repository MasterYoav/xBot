import SwiftUI
import XBotRemote

/// Abilities, like the Mac's page: connectors, plugins, skills and MCP servers for each agent.
struct AbilitiesScreen: View {
    let client: RemoteClient
    @State private var items: [RemoteAbility]?
    @State private var missing: [String] = []
    @State private var plugins: [RemotePlugin]?
    @State private var kind = "connectors"
    @State private var query = ""
    @State private var removing: RemoteAbility?
    @State private var busy: Set<String> = []
    @State private var browsing = false
    @State private var addingServer = false

    private static let kinds: [(String, String)] = [
        ("connectors", String(localized: "Connectors")), ("plugins", String(localized: "Plugins")),
        ("skills", String(localized: "Skills")), ("mcps", String(localized: "MCPs")),
    ]

    private var shown: [RemoteAbility] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return (items ?? []).filter { $0.kind == kind }
            .filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) || ($0.summary ?? "").localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !missing.isEmpty {
                    Label(String(localized: "Not on the Mac: \(missing.map { client.agent($0)?.name ?? $0 }.joined(separator: ", "))"),
                          systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.0) { agent, list in
                    Section(client.agent(agent)?.name ?? agent) {
                        ForEach(list) { ability in row(ability) }
                    }
                }
            }
            .overlay {
                if items == nil { ProgressView(String(localized: "Asking the agents…")) }
                else if shown.isEmpty {
                    ContentUnavailableView(query.isEmpty ? String(localized: "None yet") : String(localized: "Nothing matches"),
                                           systemImage: "puzzlepiece.extension")
                }
            }
            .searchable(text: $query, prompt: String(localized: "Search"))
            .refreshable { await load(refresh: true) }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker(String(localized: "Kind"), selection: $kind) {
                    ForEach(Self.kinds, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle(String(localized: "Abilities"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { browsing = true } label: { Label(String(localized: "Browse plugins"), systemImage: "bag") }
                        Button { addingServer = true } label: { Label(String(localized: "Add an MCP server"), systemImage: "server.rack") }
                        if kind == "connectors" {
                            Link(destination: URL(string: "https://claude.ai/settings/connectors")!) {
                                Label(String(localized: "Manage connectors on claude.ai"), systemImage: "safari")
                            }
                        }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel(String(localized: "Add"))
                }
            }
            .confirmationDialog(String(localized: "Remove “\(removing?.title ?? "")”?"),
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button(String(localized: "Remove"), role: .destructive) {
                    if let ability = removing { Task { await act(ability.id) { .removeAbility(requestID: $0, abilityID: ability.id) } } }
                }
            } message: { Text(String(localized: "From \(client.agent(removing?.agent ?? "")?.name ?? "the agent") on your Mac.")) }
            .sheet(isPresented: $browsing) { PluginBrowser(client: client, plugins: $plugins) { apply($0) } }
            .sheet(isPresented: $addingServer) { AddServerSheet(client: client) { apply($0) } }
        }
        .task { await load(refresh: false) }
    }

    private var groups: [(String, [RemoteAbility])] {
        let list = shown
        var order: [String] = []
        for a in list where !order.contains(a.agent) { order.append(a.agent) }
        return order.map { agent in (agent, list.filter { $0.agent == agent }) }
    }

    @ViewBuilder private func row(_ ability: RemoteAbility) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ability.title).font(.body.weight(.medium)).lineLimit(1)
                    if let status = ability.status { StatusBadge(status: status) }
                }
                if let summary = ability.summary, !summary.isEmpty {
                    Text(summary).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                } else if let source = ability.source {
                    Text(source).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if busy.contains(ability.id) {
                ProgressView()
            } else if let enabled = ability.enabled {
                if ability.canSwitch {
                    Toggle(ability.title, isOn: Binding(get: { enabled }, set: { on in
                        Task { await act(ability.id) { .setAbility(requestID: $0, abilityID: ability.id, enabled: on) } }
                    }))
                    .labelsHidden()
                } else {
                    Image(systemName: "lock.fill").foregroundStyle(.tertiary)
                        .accessibilityLabel(ability.fixedReason ?? String(localized: "Can't be switched"))
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if ability.canRemove {
                Button(role: .destructive) { removing = ability } label: { Label(String(localized: "Remove"), systemImage: "trash") }
            }
        }
    }

    private func apply(_ answer: HostMessage?) {
        guard case .abilities(_, let list, let none, let market) = answer else { return }
        items = list
        missing = none
        if let market { plugins = market }
    }

    private func load(refresh: Bool) async {
        let answer = await client.call { .listAbilities(requestID: $0, refresh: refresh) }
        if answer == nil, items == nil { items = [] }
        apply(answer)
    }

    private func act(_ id: String, _ make: (UUID) -> ClientMessage) async {
        busy.insert(id)
        defer { busy.remove(id) }
        apply(await client.call(make))
    }
}

private struct StatusBadge: View {
    let status: String
    var body: some View {
        let (text, color): (String, Color) = switch status {
        case "connected": (String(localized: "Connected"), .green)
        case "needsSignIn": (String(localized: "Needs sign-in"), .orange)
        case "failed": (String(localized: "Failed"), .red)
        default: (String(localized: "Checking"), .secondary)
        }
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

private struct PluginBrowser: View {
    let client: RemoteClient
    @Binding var plugins: [RemotePlugin]?
    let changed: (HostMessage?) -> Void
    @State private var query = ""
    @State private var installing: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach((plugins ?? []).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { plugin in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plugin.name).font(.body.weight(.medium))
                            Text("\(client.agent(plugin.agent)?.name ?? plugin.agent) · \(plugin.marketplace)").font(.caption).foregroundStyle(.secondary)
                            if let summary = plugin.summary { Text(summary).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        Spacer()
                        if plugin.installed {
                            Text(String(localized: "Installed")).font(.footnote).foregroundStyle(.secondary)
                        } else if installing == plugin.id {
                            ProgressView()
                        } else {
                            Button(String(localized: "Install")) {
                                installing = plugin.id
                                Task {
                                    let answer = await client.call { .installPlugin(requestID: $0, pluginID: plugin.id) }
                                    changed(answer)
                                    installing = nil
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .overlay { if plugins == nil { ProgressView(String(localized: "Reading the marketplaces…")) } }
            .searchable(text: $query)
            .navigationTitle(String(localized: "Plugins"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { dismiss() } } }
            .task { changed(await client.call { .listPlugins(requestID: $0) }) }
        }
    }
}

private struct AddServerSheet: View {
    let client: RemoteClient
    let added: (HostMessage?) -> Void
    @State private var name = ""
    @State private var byURL = false
    @State private var command = ""
    @State private var url = ""
    @State private var agents: Set<String> = ["claude"]
    @State private var adding = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "Name"), text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker(String(localized: "Runs"), selection: $byURL) {
                    Text(String(localized: "A command")).tag(false)
                    Text(String(localized: "At an address")).tag(true)
                }
                .pickerStyle(.segmented)
                if byURL {
                    TextField("https://…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } else {
                    TextField(String(localized: "Command, e.g. npx -y @scope/server"), text: $command)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().font(.body.monospaced())
                }
                Section(String(localized: "For")) {
                    ForEach(["claude", "codex"], id: \.self) { agent in
                        Toggle(client.agent(agent)?.name ?? agent, isOn: Binding(get: { agents.contains(agent) },
                                                                                set: { if $0 { agents.insert(agent) } else { agents.remove(agent) } }))
                    }
                }
            }
            .navigationTitle(String(localized: "Add an MCP server"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Add")) {
                        adding = true
                        let words = command.split(separator: " ").map(String.init)
                        Task {
                            let answer = await client.call {
                                .addMCP(requestID: $0, name: name, command: byURL ? nil : words.first, arguments: byURL ? [] : Array(words.dropFirst()),
                                        url: byURL ? url : nil, agents: Array(agents))
                            }
                            adding = false
                            if answer != nil { added(answer); dismiss() }
                        }
                    }
                    .disabled(adding || name.isEmpty || agents.isEmpty || (byURL ? url.isEmpty : command.isEmpty))
                }
            }
        }
    }
}
