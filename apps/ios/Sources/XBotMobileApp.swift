import SwiftUI
import UIKit
import XBotRemote
import XBotWorld

@main
struct XBotMobileApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var push
    @State private var client = RemoteClient()
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView(client: client)
                .tint(Theme.accent)
                .fontDesign(.rounded)
                // The world's animations stop while xBot isn't on screen.
                .environment(\.motionPaused, phase != .active)
                .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
                .onOpenURL { url in
                    if let invite = PairingInvite(url: url) { client.offer(invite) }
                }
                // A pairing link opened while paired replaces nothing until it's confirmed: a link
                // someone sends you shouldn't silently point this phone at their Mac.
                .alert(String(localized: "Replace the pairing with \(client.offered?.macName ?? "")?"),
                       isPresented: Binding(get: { client.offered != nil }, set: { (shown: Bool) in if !shown { client.offered = nil } })) {
                    Button(String(localized: "Replace"), role: .destructive) {
                        if let invite = client.offered { client.pair(with: invite) }
                        client.offered = nil
                    }
                    Button(String(localized: "Cancel"), role: .cancel) { client.offered = nil }
                } message: {
                    Text(String(localized: "This device will forget \(client.macName ?? String(localized: "your Mac")) and work with \(client.offered?.macName ?? "") instead."))
                }
                .onAppear {
                    PushDelegate.client = client
                    #if DEBUG
                    // Simulator tests: `SIMCTL_CHILD_XBOT_PAIR_URL=<link> xcrun simctl launch …` pairs at once.
                    if let link = ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], let url = URL(string: link),
                       let invite = PairingInvite(url: url), client.pairing?.key != invite.key {
                        client.pair(with: invite)
                    }
                    #endif
                }
        }
        .onChange(of: phase, initial: true) { _, phase in
            switch phase {
            case .active: client.start()
            case .background: client.stop()
            default: break
            }
        }
    }
}

/// iCloud's silent pushes: the Mac wrote something.
final class PushDelegate: NSObject, UIApplicationDelegate {
    @MainActor static weak var client: RemoteClient?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await Self.client?.cloudPoll()
        return .newData
    }
}

enum Theme {
    /// The colour chosen in Settings › Appearance.
    @MainActor static var accent: Color { AccentStore.shared.color }

    static func agentColor(_ id: String) -> Color { ProviderStyle.of(id).primary }
}

/// Somewhere a tab can push.
enum Destination: Hashable {
    case chat(UUID)
    case project(UUID)
    case member(UUID)
}

/// The tabs, along the bottom (a sidebar on iPad).
enum AppTab: Hashable {
    case home, chats, agents, projects, search
}

/// Places shown full screen from Home, each with its own navigation.
enum Tool: String, Identifiable, CaseIterable {
    case notes, automations, workflows, abilities, terminal, profile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: String(localized: "Notes")
        case .automations: String(localized: "Automations")
        case .workflows: String(localized: "Workflows")
        case .abilities: String(localized: "Abilities")
        case .terminal: String(localized: "Terminal")
        case .profile: String(localized: "Profile")
        }
    }

    var symbol: String {
        switch self {
        case .notes: "note.text"
        case .automations: "bolt.horizontal.fill"
        case .workflows: "point.3.connected.trianglepath.dotted"
        case .abilities: "puzzlepiece.extension.fill"
        case .terminal: "terminal.fill"
        case .profile: "person.crop.circle.fill"
        }
    }

    @MainActor var tint: Color {
        switch self {
        case .notes: .yellow
        case .automations: .orange
        case .workflows: .purple
        case .abilities: .teal
        case .terminal: .green
        case .profile: Glass.glow
        }
    }
}

/// A new chat to start, maybe in a project, maybe with text already in it.
struct ComposeRequest: Identifiable {
    let id = UUID()
    var projectID: UUID?
    var text = ""
}

/// Which tab is showing, what each has pushed, and what's presented over them.
@MainActor @Observable
final class Navigator {
    var tab = AppTab.home
    var paths: [AppTab: [Destination]] = [:]
    var tool: Tool?
    var compose: ComposeRequest?
    var addingProject = false
    var settings = false

    func path(_ tab: AppTab) -> Binding<[Destination]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    /// Shows something on the current tab.
    func push(_ destination: Destination) { paths[tab, default: []].append(destination) }

    func newChat(in projectID: UUID? = nil, text: String = "") { compose = ComposeRequest(projectID: projectID, text: text) }

    /// Leaves a chat or project that's gone.
    func drop(_ destination: Destination) {
        for key in paths.keys { paths[key]?.removeAll { $0 == destination } }
    }
}

struct RootView: View {
    let client: RemoteClient
    @State private var nav = Navigator()
    @Namespace private var tools

    var body: some View {
        if client.pairing == nil {
            PairView(client: client)
        } else {
            TabView(selection: $nav.tab) {
                Tab(String(localized: "Home"), systemImage: "sparkles", value: AppTab.home) {
                    stack(.home) { HomeScreen(client: client, nav: nav, tools: tools) }
                }
                Tab(String(localized: "Chats"), systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chats) {
                    stack(.chats) { ChatListView(client: client, nav: nav) }
                }
                Tab(String(localized: "Agents"), systemImage: "person.3.fill", value: AppTab.agents) {
                    stack(.agents) { AgentsWorldScreen(client: client, nav: nav) }
                }
                Tab(String(localized: "Projects"), systemImage: "folder.fill", value: AppTab.projects) {
                    stack(.projects) { ProjectsScreen(client: client, nav: nav) }
                }
                Tab(value: AppTab.search, role: .search) {
                    stack(.search) { SearchScreen(client: client, nav: nav) }
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewStyle(.sidebarAdaptable)
            .sheet(isPresented: $nav.settings) { SettingsSheet(client: client) }
            .sheet(item: $nav.compose) { request in
                NewChatSheet(client: client, initialProject: request.projectID, initialText: request.text) { id in
                    nav.compose = nil
                    nav.push(.chat(id))
                }
            }
            .sheet(isPresented: $nav.addingProject) {
                AddProjectSheet(client: client) { id in
                    nav.addingProject = false
                    if let id { nav.tab = .projects; nav.paths[.projects] = [.project(id)] }
                }
            }
            .fullScreenCover(item: $nav.tool) { tool in
                Group {
                    switch tool {
                    case .notes: NotesScreen(client: client)
                    case .automations: AutomationsScreen(client: client)
                    case .workflows: WorkflowsScreen(client: client)
                    case .abilities: AbilitiesScreen(client: client)
                    case .profile: ProfileScreen(client: client)
                    case .terminal: NavigationStack { TerminalScreen(client: client, projectID: nil).closable() }
                    }
                }
                .environment(\.close, { nav.tool = nil })
                .navigationTransition(.zoom(sourceID: tool, in: tools))
            }
            .alert(String(localized: "Your Mac said no"), isPresented: Binding(get: { client.notice != nil }, set: { if !$0 { client.notice = nil } })) {
                Button(String(localized: "OK")) { client.notice = nil }
            } message: {
                Text(client.notice ?? "")
            }
        }
    }

    private func stack(_ tab: AppTab, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: nav.path(tab)) {
            root()
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .chat(let id):
                        ChatScreen(client: client, chatID: id).id(id)
                            .toolbar(.hidden, for: .tabBar)
                    case .project(let id):
                        ProjectScreen(client: client, projectID: id) { project, text in nav.newChat(in: project, text: text) }
                            .id(id)
                    case .member(let id):
                        CrewMemberScreen(client: client, nav: nav, memberID: id)
                    }
                }
        }
    }
}

/// Where the Mac is: a line under the title.
struct LinkStatus: View {
    let client: RemoteClient

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("link-status")
    }

    private var text: String { Self.text(client) }
    private var color: Color { Self.color(client) }

    static func text(_ client: RemoteClient) -> String {
        let mac = client.macName ?? String(localized: "your Mac")
        return switch client.link {
        case .unpaired: String(localized: "Not paired")
        case .searching: String(localized: "Looking for \(mac)…")
        case .local: String(localized: "\(mac) · same Wi-Fi")
        case .cloud: String(localized: "\(mac) · through iCloud")
        case .unreachable(let why): why
        }
    }

    static func color(_ client: RemoteClient) -> Color {
        switch client.link {
        case .local, .cloud: .green
        case .searching: .orange
        case .unpaired, .unreachable: .red
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
    var title: String {
        switch self {
        case .system: String(localized: "Match the device")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

struct SettingsSheet: View {
    let client: RemoteClient
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("markdownAsCode") private var markdownAsCode = false
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(String(localized: "Mac"), value: client.macName ?? "—")
                    LinkStatus(client: client)
                } footer: {
                    Text(String(localized: "The agents run on your Mac. Keep it on and awake; while this device is connected, xBot keeps it from sleeping."))
                }
                Section(String(localized: "Appearance")) {
                    Picker(String(localized: "Look"), selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    AccentPicker()
                } header: {
                    Text(String(localized: "Accent colour"))
                } footer: {
                    Text(String(localized: "Used for buttons, highlights and Home's glow."))
                }
                Section(String(localized: "Files")) {
                    Toggle(String(localized: "Show .md files as code"), isOn: $markdownAsCode)
                }
                Section {
                    Button(String(localized: "Unpair this device"), role: .destructive) { confirming = true }
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { dismiss() } } }
            .confirmationDialog(String(localized: "Unpair from \(client.macName ?? "your Mac")?"), isPresented: $confirming, titleVisibility: .visible) {
                Button(String(localized: "Unpair"), role: .destructive) { client.unpair(); dismiss() }
            } message: {
                Text(String(localized: "To use xBot here again, pair it from the Mac's Settings › Devices."))
            }
        }
    }
}
