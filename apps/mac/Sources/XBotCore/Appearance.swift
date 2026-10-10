import AppKit
import Foundation
import Observation

/// Settings › Appearance: light or dark, the picture behind the main screen, the typeface and the
/// app icon.
///
/// One shared, observable object, because the window, the Settings window and the design system's
/// type scale all read it, and a change has to reach all three at once.
@MainActor @Observable
public final class Appearance {
    public enum Theme: String, CaseIterable, Sendable {
        case dark, light, system

        public var title: String {
            switch self {
            case .dark: String(localized: "Dark")
            case .light: String(localized: "Light")
            case .system: String(localized: "Match System")
            }
        }

        /// What `NSApp.appearance` is set to. Nil follows the system.
        public var nsAppearance: NSAppearance? {
            switch self {
            case .dark: NSAppearance(named: .darkAqua)
            case .light: NSAppearance(named: .aqua)
            case .system: nil
            }
        }
    }

    public enum Wallpaper: Equatable, Sendable {
        /// The sunset xBot ships with.
        case sunset
        /// The picture on the person's desktop right now.
        case desktop
        /// A picture of their own, copied into xBot's folder.
        case custom(URL)
        case none
    }

    /// The app icon: one colour of xBot.icon. Ink is the one the app ships with.
    public enum AppIcon: String, CaseIterable, Sendable {
        case ink, rose, sunset, plum

        public var title: String {
            switch self {
            case .ink: String(localized: "Ink")
            case .rose: String(localized: "Rose")
            case .sunset: String(localized: "Sunset")
            case .plum: String(localized: "Plum")
            }
        }

        public var isDefault: Bool { self == .ink }
    }

    public static let shared = Appearance()

    public var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: Keys.theme) } }

    public var wallpaper: Wallpaper {
        didSet {
            switch wallpaper {
            case .sunset: defaults.set("sunset", forKey: Keys.wallpaper)
            case .desktop: defaults.set("desktop", forKey: Keys.wallpaper)
            case .none: defaults.set("none", forKey: Keys.wallpaper)
            case .custom(let url):
                defaults.set("custom", forKey: Keys.wallpaper)
                defaults.set(url.lastPathComponent, forKey: Keys.customFile)
            }
        }
    }

    public var appIcon: AppIcon { didSet { defaults.set(appIcon.rawValue, forKey: Keys.appIcon) } }

    /// A family from the Mac's own fonts. Nil is the system font, SF Pro.
    public var fontFamily: String? { didSet { defaults.set(fontFamily, forKey: Keys.fontFamily) } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let folder: URL

    private enum Keys {
        static let theme = "theme"
        static let wallpaper = "wallpaper"
        static let customFile = "wallpaperFile"
        static let fontFamily = "fontFamily"
        static let appIcon = "appIcon"
        /// Settings › General › Background picture, before Appearance existed.
        static let legacyBackdrop = "showBackdrop"
    }

    public init(
        defaults: UserDefaults = .standard,
        folder: URL = Store.supportDirectory,
        installedFamilies: () -> [String] = { NSFontManager.shared.availableFontFamilies }
    ) {
        self.defaults = defaults
        self.folder = folder
        theme = defaults.string(forKey: Keys.theme).flatMap(Theme.init(rawValue:)) ?? .dark
        appIcon = defaults.string(forKey: Keys.appIcon).flatMap(AppIcon.init(rawValue:)) ?? .ink

        switch defaults.string(forKey: Keys.wallpaper) {
        case "desktop": wallpaper = .desktop
        case "none": wallpaper = .none
        case "custom":
            let file = defaults.string(forKey: Keys.customFile).map { folder.appending(path: $0) }
            if let file, FileManager.default.fileExists(atPath: file.path) {
                wallpaper = .custom(file)
            } else {
                wallpaper = .sunset
            }
        case "sunset": wallpaper = .sunset
        default:
            wallpaper = defaults.object(forKey: Keys.legacyBackdrop) as? Bool == false ? .none : .sunset
        }

        if let family = defaults.string(forKey: Keys.fontFamily), installedFamilies().contains(family) {
            fontFamily = family
        } else {
            fontFamily = nil
        }
    }

    /// Copies the picture into xBot's folder and uses the copy. The original can then move or go.
    public func useCustomPicture(at url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension.lowercased()
        let destination = folder.appending(path: "wallpaper.\(ext)")
        let staged = folder.appending(path: ".wallpaper-incoming.\(ext)")
        try? fm.removeItem(at: staged)
        try fm.copyItem(at: url, to: staged)
        // Earlier pictures, whatever their extension: only the one in use is kept.
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix("wallpaper.") {
            try? fm.removeItem(at: folder.appending(path: name))
        }
        try fm.moveItem(at: staged, to: destination)
        wallpaper = .custom(destination)
    }

    /// The families worth offering: no hidden system ones (".AppleSystemUIFont"), each once, A–Z.
    public static func fontFamilies(from all: [String] = NSFontManager.shared.availableFontFamilies) -> [String] {
        var seen = Set<String>()
        return all
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .filter { seen.insert($0.lowercased()).inserted }
    }
}
