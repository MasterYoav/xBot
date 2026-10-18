#if DEBUG
import SwiftUI

/// Debug only: `XBOT_SCENE=<Name>` shows one onboarding scene in the window instead of the app, at
/// the onboarding's default scene size (or `XBOT_SCENE_SIZE=WxH`), so each scene can be looked at
/// and screenshotted on its own. Wired into `RootView` under `#if DEBUG`.
struct ScenePreviewHost: View {
    let name: String

    static var requested: String? {
        ProcessInfo.processInfo.environment["XBOT_SCENE"].flatMap { $0.isEmpty ? nil : $0 }
    }

    private var size: CGSize {
        let parts = (ProcessInfo.processInfo.environment["XBOT_SCENE_SIZE"] ?? "")
            .split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return SceneMetrics.canvas }
        return CGSize(width: parts[0], height: parts[1])
    }

    var body: some View {
        VStack(spacing: Space.l) {
            scene
                .frame(width: size.width, height: size.height)
            Text(verbatim: "\(name) · \(Int(size.width)) × \(Int(size.height))")
                .labelText()
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.window)
    }

    @ViewBuilder
    private var scene: some View {
        switch name.lowercased().replacingOccurrences(of: "scene", with: "") {
        case "welcome": WelcomeScene()
        case "chats": ChatsScene()
        case "plan": PlanScene()
        case "inspector": InspectorScene()
        case "crew": CrewScene()
        case "extras": ExtrasScene()
        case "files": FilesScene()
        case "phone": PhoneScene()
        case "worlds": WorldsScene()
        case "ready": ReadyScene()
        default: Text(verbatim: "No scene named \(name)").foregroundStyle(Palette.textSecondary)
        }
    }
}
#endif
