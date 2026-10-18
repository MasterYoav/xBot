import AppKit
import SwiftUI
import XBotCore

/// The Settings window (⌘,): how new chats start, how xBot looks, the agents found, and about xBot.
public struct SettingsView: View {
    let workspace: Workspace

    public init(workspace: Workspace) { self.workspace = workspace }

    public var body: some View {
        TabView {
            GeneralSettings(workspace: workspace)
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            AppearanceSettings(workspace: workspace)
                .tabItem { Label(String(localized: "Appearance"), systemImage: "paintpalette") }
            AgentSettings(workspace: workspace)
                .tabItem { Label(String(localized: "Agents"), systemImage: "cpu") }
            DevicesSettings(workspace: workspace)
                .tabItem { Label(String(localized: "Devices"), systemImage: "iphone") }
            AboutSettings()
                .tabItem { Label(String(localized: "About"), systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
    }
}

private struct GeneralSettings: View {
    let workspace: Workspace
    // Local copies: the defaults live in UserDefaults, which observation does not see.
    @State private var harness: HarnessKind?
    @State private var effort: Effort?
    @State private var mode = PermissionMode.editFiles

    var body: some View {
        Form {
            Picker(String(localized: "Default agent"), selection: $harness) {
                Text(String(localized: "Most recent")).tag(HarnessKind?.none)
                ForEach(HarnessKind.allCases, id: \.self) { Text($0.displayName).tag(HarnessKind?.some($0)) }
            }
            Picker(String(localized: "Default reasoning"), selection: $effort) {
                Text(String(localized: "The agent's default")).tag(Effort?.none)
                ForEach(Effort.allCases, id: \.self) { Text($0.title).tag(Effort?.some($0)) }
            }
            Picker(String(localized: "Default permission"), selection: $mode) {
                ForEach(PermissionMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            harness = workspace.defaultHarness
            effort = workspace.defaultEffort
            mode = workspace.defaultMode
        }
        .onChange(of: harness) { workspace.defaultHarness = harness }
        .onChange(of: effort) { workspace.defaultEffort = effort }
        .onChange(of: mode) { workspace.defaultMode = mode }
    }
}

private struct AgentSettings: View {
    let workspace: Workspace

    var body: some View {
        Form {
            ForEach(HarnessKind.allCases, id: \.self) { kind in
                Section(kind.displayName) {
                    LabeledContent(String(localized: "Found at")) {
                        Text(workspace.executable(for: kind)?.path(percentEncoded: false)
                             ?? (workspace.isDiscovering ? String(localized: "Looking…") : String(localized: "Not installed")))
                            .font(Typography.mono)
                            .textSelection(.enabled)
                    }
                    LabeledContent(String(localized: "Signed in"), value: signedIn(kind))
                    if let plan = plan(kind) { LabeledContent(String(localized: "Plan"), value: plan) }
                    if let limits = workspace.usage[kind]?.limits {
                        if let window = limits.fiveHour {
                            LabeledContent(String(localized: "5-hour usage left"),
                                           value: "\(UsageText.remaining(window)) · \(UsageText.resets(window.resetsAt))")
                        }
                        if let window = limits.weekly {
                            LabeledContent(String(localized: "Weekly usage left"),
                                           value: "\(UsageText.remaining(window)) · \(UsageText.resets(window.resetsAt))")
                        }
                    }
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button(String(localized: "Look Again")) { Task { await workspace.refreshHarnesses() } }
                        .disabled(workspace.isDiscovering)
                }
            }
            XBotToolsSettings(workspace: workspace)
        }
        .formStyle(.grouped)
        .task { await workspace.refreshCodexUsage() }
    }

    /// Claude Code says in its account summary; Codex only shows it by reporting a plan.
    private func signedIn(_ kind: HarnessKind) -> String {
        switch kind {
        case .claude: ClaudeAccount.isSignedIn() ? String(localized: "Yes") : String(localized: "No")
        case .codex: workspace.usage[.codex]?.limits.plan != nil ? String(localized: "Yes") : String(localized: "Not seen yet")
        case .antigravity, .copilot: String(localized: "Checked on the first turn")
        }
    }

    private func plan(_ kind: HarnessKind) -> String? {
        kind == .claude ? workspace.claudePlan : workspace.usage[.codex]?.limits.plan
    }
}

/// Agentic Mode's tools: whether every chat gets them, the two Mac permissions they need, and
/// Antigravity's copy of xBot's server.
private struct XBotToolsSettings: View {
    let workspace: Workspace
    @AppStorage("agentic.toolsEverywhere") private var everywhere = false
    @State private var allowed: [MacPermission: Bool] = [:]
    @State private var antigravity = false

    var body: some View {
        Section {
            Toggle(String(localized: "xBot tools in every chat"), isOn: $everywhere)
            Text(String(localized: "Agents in any chat can then use xBot and your Mac: projects, chats, the crew, automations, notes, screenshots, clicks and typing. Deleting, sending, pushing, buying, quitting apps and changing settings always ask you first. Threads with your agents have the tools either way."))
                .captionText().foregroundStyle(Palette.textSecondary)
            ForEach(MacPermission.allCases, id: \.self) { permission in
                LabeledContent(title(permission)) {
                    if allowed[permission] == true {
                        Label(String(localized: "Allowed"), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.success)
                    } else {
                        Button(String(localized: "Allow…")) { MacPermissionGuide.show(permission) }
                    }
                }
            }
            if antigravity {
                LabeledContent(String(localized: "Antigravity")) {
                    Button(String(localized: "Remove xBot's Tools")) {
                        Task {
                            await workspace.removeAntigravityTools()
                            antigravity = workspace.antigravityHasTools
                        }
                    }
                }
                Text(String(localized: "Antigravity keeps xBot's tools in its own settings. Outside xBot they can't do anything."))
                    .captionText().foregroundStyle(Palette.textSecondary)
            }
        } header: {
            Text(String(localized: "xBot tools"))
        }
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        allowed = Dictionary(uniqueKeysWithValues: MacPermission.allCases.map { ($0, MacControlAccess.isAllowed($0)) })
        antigravity = workspace.antigravityHasTools
    }

    private func title(_ permission: MacPermission) -> String {
        switch permission {
        case .accessibility: String(localized: "Accessibility (read the screen, click, type)")
        case .screenRecording: String(localized: "Screen Recording (screenshots)")
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: Space.m) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: Space.xxl * 2, height: Space.xxl * 2)
            Text(verbatim: "xBot").titleText()
            Text(version).captionText().foregroundStyle(Palette.textTertiary)
            Text(AttributedString(AboutPanel.credits))
                .multilineTextAlignment(.center)
                .frame(maxWidth: Metrics.effortCardWidth + Space.xxl)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return String(localized: "Version \(short) (\(build))")
    }
}
