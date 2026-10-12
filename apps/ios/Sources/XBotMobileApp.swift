import SwiftUI
import UIKit
import XBotRemote

@main
struct XBotMobileApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var push
    @State private var client = RemoteClient()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView(client: client)
                .tint(Theme.accent)
                .onOpenURL { url in
                    if let invite = PairingInvite(url: url) { client.pair(with: invite) }
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
    static let accent = Color(red: 0.71, green: 0.37, blue: 0.55)

    static func agentColor(_ id: String) -> Color {
        switch id {
        case "claude": Color(red: 0.85, green: 0.47, blue: 0.34)
        case "codex": .primary
        case "antigravity": Color(red: 0.10, green: 0.45, blue: 0.91)
        case "copilot": Color(red: 0.51, green: 0.31, blue: 0.87)
        default: .secondary
        }
    }
}

/// What the detail column shows.
enum Destination: Hashable {
    case chat(UUID)
    case project(UUID)
    case notes
    case automations
    case agents
}

/// A new chat to start, maybe in a project, maybe with text already in it.
struct ComposeRequest: Identifiable {
    let id = UUID()
    var projectID: UUID?
    var text = ""
}

struct RootView: View {
    let client: RemoteClient
    @State private var selection: Destination?
    @State private var settings = false
    @State private var compose: ComposeRequest?
    @State private var addingProject = false

    var body: some View {
        if client.pairing == nil {
            PairView(client: client)
        } else {
            NavigationSplitView {
                ChatListView(client: client, selection: $selection, showSettings: { settings = true },
                             compose: { compose = ComposeRequest(projectID: $0, text: $1) },
                             addProject: { addingProject = true })
            } detail: {
                switch selection {
                case .chat(let id) where client.chat(id) != nil:
                    ChatScreen(client: client, chatID: id).id(id)
                case .project(let id) where client.project(id) != nil:
                    ProjectScreen(client: client, projectID: id) { project, text in
                        compose = ComposeRequest(projectID: project, text: text)
                    }
                    .id(id)
                case .notes:
                    NotesScreen(client: client)
                case .automations:
                    AutomationsScreen(client: client)
                case .agents:
                    CrewScreen(client: client)
                default:
                    ContentUnavailableView(String(localized: "Choose a chat"), systemImage: "bubble.left.and.text.bubble.right",
                                           description: Text(String(localized: "Or start a new one with ✎.")))
                }
            }
            .sheet(isPresented: $settings) { SettingsSheet(client: client) }
            .sheet(item: $compose) { request in
                NewChatSheet(client: client, initialProject: request.projectID, initialText: request.text) { id in
                    compose = nil
                    selection = .chat(id)
                }
            }
            .sheet(isPresented: $addingProject) {
                AddProjectSheet(client: client) { id in
                    addingProject = false
                    if let id { selection = .project(id) }
                }
            }
            .alert(String(localized: "Your Mac said no"), isPresented: Binding(get: { client.notice != nil }, set: { if !$0 { client.notice = nil } })) {
                Button(String(localized: "OK")) { client.notice = nil }
            } message: {
                Text(client.notice ?? "")
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

    private var mac: String { client.macName ?? String(localized: "your Mac") }

    private var text: String {
        switch client.link {
        case .unpaired: String(localized: "Not paired")
        case .searching: String(localized: "Looking for \(mac)…")
        case .local: String(localized: "\(mac) · same Wi-Fi")
        case .cloud: String(localized: "\(mac) · through iCloud")
        case .unreachable(let why): why
        }
    }

    private var color: Color {
        switch client.link {
        case .local, .cloud: .green
        case .searching: .orange
        case .unpaired, .unreachable: .red
        }
    }
}

struct SettingsSheet: View {
    let client: RemoteClient
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
