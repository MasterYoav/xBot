import AppKit
import SwiftUI
import XBotCore

/// Puts the chosen colour of the xBot icon where people see it.
///
/// Two places, because macOS keeps two: the Dock tile of the running app (`applicationIconImage`,
/// gone when the app quits), and the icon of the app bundle itself — Finder, Launchpad, the Dock
/// while xBot is closed — which `NSWorkspace.setIcon` stores beside the bundle's contents. Normal
/// code-signature checks still pass with it; an update replaces the bundle and drops it, which is
/// why this runs at every launch as well as on every change. Ink, the icon the app ships with, puts
/// both back to the bundle's own.
@MainActor
public enum AppIconApplier {
    public static func image(for icon: Appearance.AppIcon) -> NSImage? {
        Bundle.module.url(forResource: icon.rawValue, withExtension: "icns", subdirectory: "AppIcons")
            .flatMap(NSImage.init(contentsOf:))
    }

    public static func apply(_ icon: Appearance.AppIcon) {
        let image = icon.isDefault ? nil : image(for: icon)
        NSApp.applicationIconImage = image
        // Only an installed app: `swift run` has no bundle to put an icon on.
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app", FileManager.default.isWritableFile(atPath: bundle.path) else { return }
        NSWorkspace.shared.setIcon(image, forFile: bundle.path, options: [])
    }
}

extension View {
    /// Settings › Appearance › App icon, applied at launch and whenever it changes.
    public func followsAppIconSetting() -> some View {
        onChange(of: Appearance.shared.appIcon, initial: true) { _, icon in AppIconApplier.apply(icon) }
    }
}
