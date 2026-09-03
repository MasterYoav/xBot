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
        .navigationTitle(String(localized: "Advanced"))
    }
}

public struct SettingsRootView: View {
    public init() {}

    public var body: some View {
        TabView {
            ModelsSettingsView()
                .tabItem { Label(String(localized: "Models"), systemImage: "cpu") }

            AdvancedSettingsView()
                .tabItem { Label(String(localized: "Advanced"), systemImage: "slider.horizontal.3") }
        }
        // Taller than the old placeholder: Models lists five providers and grows a key field.
        .frame(width: 560, height: 460)
    }
}
