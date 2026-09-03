import SwiftUI
import XBotCore
import XBotEngine

/// The upstream plugins admin UI, embedded per ADR-0004.
public struct PluginsAdminView: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        Group {
            if let url = state.pluginsAdminURL, let token = state.pluginsAdminToken {
                AdminWebView(url: url, bearerToken: token)
                    .id(state.pluginsAdminDeepLink)
            } else {
                unavailable
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(Palette.windowBackground)
    }

    private var unavailable: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Palette.textSecondary)
            Text(String(localized: "Plugins need a running engine"))
                .sectionTitle()
            Text(String(localized: "Start the engine from onboarding or the main window, then open Plugins again."))
                .bodyText()
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if state.composerBlock == .engineNotRunning || state.composerBlock?.isEngineFailure == true {
                Button(String(localized: "Start engine")) {
                    state.startEngine()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xl)
    }
}

private extension ComposerBlock {
    var isEngineFailure: Bool {
        if case .engineFailed = self { return true }
        return false
    }
}
