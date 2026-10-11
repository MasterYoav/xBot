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
            AppearanceSettings()
                .tabItem { Label(String(localized: "Appearance"), systemImage: "paintpalette") }
            AgentSettings(workspace: workspace)
                .tabItem { Label(String(localized: "Agents"), systemImage: "cpu") }
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
        }
        .formStyle(.grouped)
        .task { await workspace.refreshCodexUsage() }
    }

    /// Claude Code says in its account summary; Codex only shows it by reporting a plan.
    private func signedIn(_ kind: HarnessKind) -> String {
        switch kind {
        case .claude: ClaudeAccount.isSignedIn() ? String(localized: "Yes") : String(localized: "No")
        case .codex: workspace.usage[.codex]?.limits.plan != nil ? String(localized: "Yes") : String(localized: "Not seen yet")
        }
    }

    private func plan(_ kind: HarnessKind) -> String? {
        kind == .claude ? workspace.claudePlan : workspace.usage[.codex]?.limits.plan
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
