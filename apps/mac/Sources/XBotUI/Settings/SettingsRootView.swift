import SwiftUI
import XBotCore

/// Settings → Advanced. Admin surfaces live here per ADR-0004.
public struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    public var body: some View {
        Form {
            Section {
                Button(String(localized: "Plugins…")) {
                    state.preparePluginsAdmin()
                    openWindow(id: "plugins-admin")
                }
            } header: {
                Text(String(localized: "Admin"))
            } footer: {
                Text(
                    String(
                        localized:
                            "Connect third-party services and choose which agents may use their tools. Opens the engine's plugins manager."
                    )
                )
            }
        }
        .formStyle(.grouped)
    }
}

/// Settings, in the window rather than in a floating panel.
///
/// A list on the left and the pane on the right, which is the shape macOS System Settings uses and
/// the one the rail already establishes in this window. It replaces the conversation rather than
/// covering it, so the rail stays visible and it is always clear which agent is selected while its
/// model is being changed.
public struct SettingsRootView: View {
    @Environment(AppState.self) private var state
    @State private var section: Section = .models

    enum Section: String, CaseIterable, Identifiable {
        case models
        case advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .models: String(localized: "Models")
            case .advanced: String(localized: "Advanced")
            }
        }

        var symbol: String {
            switch self {
            case .models: "cpu"
            case .advanced: "slider.horizontal.3"
            }
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.separator.opacity(0.35))
            HStack(spacing: 0) {
                sidebar
                Divider().overlay(Palette.separator.opacity(0.35))
                pane
            }
        }
        .background(Palette.windowBackground)
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            // Exits the way it arrived — docs/08-design-system.md: enter and exit along the same
            // path. Escape does the same thing, for the same reason.
            Button {
                withAnimation(Motion.panel) { state.isShowingSettings = false }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close settings"))

            Text(String(localized: "Settings")).bodyEmphasis()
            Spacer()
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            ForEach(Section.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: Space.s) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13))
                            .frame(width: 18)
                        Text(item.title).bodyText()
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .background(
                        section == item ? Palette.elevatedSurface : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(section == item ? Palette.textPrimary : Palette.textSecondary)
            }
            Spacer()
        }
        .padding(Space.s)
        .frame(width: 180, alignment: .leading)
    }

    @ViewBuilder
    private var pane: some View {
        switch section {
        case .models: ModelsSettingsView()
        case .advanced: AdvancedSettingsView()
        }
    }
}
