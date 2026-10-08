import SwiftUI
import XBotCore

/// The sidebar's footer: your picture and name. It opens a small card — who you are, the usage
/// your agents have left, Profile and Settings.
struct AccountButton: View {
    let workspace: Workspace
    @State private var open = false
    @State private var hovering = false
    private let identity = Identity.shared

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: Space.s) {
                Avatar(identity: identity, size: Metrics.avatarSmall)
                Text(identity.name).emphasisText().foregroundStyle(Palette.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(hovering || open ? Palette.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(XBotButtonStyle())
        .onHover { hovering = $0 }
        .padding(Space.s)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
        .popover(isPresented: $open, arrowEdge: .top) {
            AccountMenu(workspace: workspace, identity: identity, close: { open = false })
        }
        .accessibilityLabel(String(localized: "Account: \(identity.name)"))
    }
}

struct AccountMenu: View {
    let workspace: Workspace
    let identity: Identity
    let close: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.m) {
                Avatar(identity: identity, size: Metrics.avatarMenu)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(identity.name).emphasisText().foregroundStyle(Palette.textPrimary)
                    Text(plans).captionText().foregroundStyle(Palette.textTertiary).lineLimit(1)
                }
            }
            .padding(Space.s)
            Divider().padding(.horizontal, Space.s)
            UsageSection(workspace: workspace)
            Divider().padding(.horizontal, Space.s)
            row(String(localized: "Profile"), systemImage: "person.crop.circle") {
                workspace.page = .profile
                close()
            }
            row(String(localized: "Settings"), systemImage: "gearshape", shortcut: "⌘,") {
                close()
                openSettings()
            }
        }
        .padding(Space.xs)
        .frame(width: Metrics.accountMenuWidth)
    }

    /// "Claude Max · ChatGPT Plus": the plans the agents report.
    private var plans: String {
        let known = [workspace.claudePlan, workspace.usage[.codex]?.limits.plan].compactMap { $0 }
        return known.isEmpty ? String(localized: "Claude Code · Codex") : known.joined(separator: " · ")
    }

    private func row(_ title: String, systemImage: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SidebarRow(title, systemImage: systemImage) {
                if let shortcut { MonoLabel(shortcut) }
            }
        }
        .buttonStyle(.plain)
    }
}
