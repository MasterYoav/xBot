import SwiftUI

// Stand-ins for the animated scenes, so the onboarding shell builds on its own. The real scenes
// (same names, no-argument inits) replace this file.

private struct ScenePlaceholder: View {
    let title: String
    let symbol: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous).fill(Palette.inset)
            VStack(spacing: Space.s) {
                Image(systemName: symbol).font(Typography.hero).foregroundStyle(Palette.textTertiary)
                Text(title).labelText().foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

struct WelcomeScene: View {
    var body: some View { ScenePlaceholder(title: "Welcome scene", symbol: "sparkles") }
}

struct ChatsScene: View {
    var body: some View { ScenePlaceholder(title: "Chats scene", symbol: "bubble.left.and.bubble.right") }
}

struct PlanScene: View {
    var body: some View { ScenePlaceholder(title: "Plan scene", symbol: "list.bullet.clipboard") }
}

struct InspectorScene: View {
    var body: some View { ScenePlaceholder(title: "Inspector scene", symbol: "sidebar.right") }
}

struct CrewScene: View {
    var body: some View { ScenePlaceholder(title: "Crew scene", symbol: "person.3") }
}

struct ExtrasScene: View {
    var body: some View { ScenePlaceholder(title: "Extras scene", symbol: "square.stack.3d.up") }
}

struct FilesScene: View {
    var body: some View { ScenePlaceholder(title: "Files scene", symbol: "folder") }
}

struct PhoneScene: View {
    var body: some View { ScenePlaceholder(title: "Phone scene", symbol: "iphone") }
}

struct WorldsScene: View {
    var body: some View { ScenePlaceholder(title: "Worlds scene", symbol: "globe") }
}

struct ReadyScene: View {
    var body: some View { ScenePlaceholder(title: "Ready scene", symbol: "checkmark.seal") }
}
