import AppKit
import SwiftUI
import UniformTypeIdentifiers
import XBotCore

/// Settings › Appearance: light or dark, the wallpaper behind the main screen, and the typeface.
struct AppearanceSettings: View {
    @Bindable private var appearance = Appearance.shared
    @State private var choosingPicture = false
    @State private var problem: String?
    private let families = Appearance.fontFamilies()

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Appearance"), selection: $appearance.theme) {
                    ForEach(Appearance.Theme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section(String(localized: "Wallpaper")) {
                HStack(spacing: Space.m) {
                    tile(.sunset, title: String(localized: "Sunset"))
                    tile(.desktop, title: String(localized: "Desktop"))
                    customTile
                    tile(.none, title: String(localized: "None"))
                }
                .padding(.vertical, Space.xs)
                if let problem {
                    Text(problem).captionText().foregroundStyle(Palette.failure)
                }
            }

            Section(String(localized: "Font")) {
                Picker(String(localized: "Typeface"), selection: $appearance.fontFamily) {
                    Text(String(localized: "System (SF Pro)")).tag(String?.none)
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Text(String(localized: "The quick brown fox asks the agent to jump over the lazy bug."))
                    .readingText()
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(localized: "Code and file names stay in SF Mono."))
                    .captionText()
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosingPicture, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                if case .custom(let old) = appearance.wallpaper { PictureCache.forget(old) }
                try appearance.useCustomPicture(at: url)
                if case .custom(let new) = appearance.wallpaper { PictureCache.forget(new) }
                problem = nil
            } catch {
                problem = String(localized: "xBot couldn't use that picture: \(error.localizedDescription)")
            }
        }
    }

    private func tile(_ wallpaper: Appearance.Wallpaper, title: String) -> some View {
        Button { appearance.wallpaper = wallpaper } label: {
            Thumbnail(image: Backdrop.image(for: wallpaper), title: title,
                      selected: appearance.wallpaper == wallpaper, systemImage: wallpaper == .none ? "slash.circle" : nil)
        }
        .buttonStyle(.plain)
    }

    /// The person's own picture: shows it once chosen; clicking it again picks another.
    private var customTile: some View {
        Button { choosingPicture = true } label: {
            let current: NSImage? = if case .custom = appearance.wallpaper { Backdrop.image(for: appearance.wallpaper) } else { nil }
            let isCustom: Bool = if case .custom = appearance.wallpaper { true } else { false }
            Thumbnail(image: current, title: String(localized: "Choose…"), selected: isCustom,
                      systemImage: current == nil ? "photo.badge.plus" : nil)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Use a picture of your own"))
    }
}

private struct Thumbnail: View {
    let image: NSImage?
    let title: String
    let selected: Bool
    var systemImage: String?

    var body: some View {
        VStack(spacing: Space.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Palette.inset)
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else if let systemImage {
                    Image(systemName: systemImage).font(Typography.title).foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(width: Metrics.wallpaperThumb.width, height: Metrics.wallpaperThumb.height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(selected ? Palette.accent : Palette.hairline, lineWidth: selected ? 2 : 1)
            )
            Text(title).captionText().foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

extension View {
    /// Applies Settings › Appearance › Appearance to the whole app — every window, menus and sheets —
    /// through `NSApp.appearance`, which the palette's light/dark colours resolve against.
    public func followsAppearanceSetting() -> some View {
        modifier(ThemeFollower())
    }
}

private struct ThemeFollower: ViewModifier {
    func body(content: Content) -> some View {
        content.onChange(of: Appearance.shared.theme, initial: true) { _, theme in
            NSApp.appearance = theme.nsAppearance
        }
    }
}
