import Foundation
import Testing
@testable import XBotCore

@MainActor @Suite struct AppearanceTests {
    func fresh() -> (UserDefaults, URL) {
        let name = "appearance-\(UUID().uuidString)"
        let folder = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        return (UserDefaults(suiteName: name)!, folder)
    }

    @Test func darkSunsetAndTheSystemFontByDefault() {
        let (defaults, folder) = fresh()
        let a = Appearance(defaults: defaults, folder: folder)
        #expect(a.theme == .dark)
        #expect(a.wallpaper == .sunset)
        #expect(a.fontFamily == nil)
    }

    @Test func choicesAreKeptAcrossLaunches() {
        let (defaults, folder) = fresh()
        let a = Appearance(defaults: defaults, folder: folder)
        a.theme = .light
        a.wallpaper = .none
        a.fontFamily = "Avenir Next"
        let b = Appearance(defaults: defaults, folder: folder)
        #expect(b.theme == .light && b.wallpaper == .none && b.fontFamily == "Avenir Next")
    }

    /// The old Settings toggle, "Background picture", switched off: the picture stays off.
    @Test func theOldBackgroundToggleCarriesOver() {
        let (defaults, folder) = fresh()
        defaults.set(false, forKey: "showBackdrop")
        #expect(Appearance(defaults: defaults, folder: folder).wallpaper == .none)
    }

    /// A picture of the person's own is copied into xBot's folder, so moving or deleting the
    /// original does not take the wallpaper with it.
    @Test func aCustomPictureIsCopiedAndSurvivesTheOriginal() throws {
        let (defaults, folder) = fresh()
        let original = FileManager.default.temporaryDirectory.appending(path: "pic-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: original)
        let a = Appearance(defaults: defaults, folder: folder)
        try a.useCustomPicture(at: original)
        try FileManager.default.removeItem(at: original)

        guard case .custom(let url) = a.wallpaper else { Issue.record("not custom: \(a.wallpaper)"); return }
        #expect(url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(Appearance(defaults: defaults, folder: folder).wallpaper == .custom(url))
    }

    /// Choosing another picture replaces the copy rather than piling them up.
    @Test func aSecondCustomPictureReplacesTheFirst() throws {
        let (defaults, folder) = fresh()
        let a = Appearance(defaults: defaults, folder: folder)
        for ext in ["png", "jpg"] {
            let original = FileManager.default.temporaryDirectory.appending(path: "pic-\(UUID().uuidString).\(ext)")
            try Data([1, 2, 3]).write(to: original)
            try a.useCustomPicture(at: original)
        }
        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("wallpaper") }
        #expect(kept == ["wallpaper.jpg"])
    }

    /// A custom picture whose copy has gone (the library was cleaned) falls back to the sunset
    /// rather than an empty window.
    @Test func aMissingCustomPictureFallsBackToTheSunset() {
        let (defaults, folder) = fresh()
        defaults.set("custom", forKey: "wallpaper")
        #expect(Appearance(defaults: defaults, folder: folder).wallpaper == .sunset)
    }

    @Test func fontFamiliesAreTheVisibleOnesSortedWithoutDuplicates() {
        let families = Appearance.fontFamilies(from: ["Zapfino", ".AppleSystemUIFont", "Avenir", "avenir", "Menlo"])
        #expect(families == ["Avenir", "Menlo", "Zapfino"])
    }

    /// A font that was uninstalled since it was chosen is forgotten, not drawn as a fallback.
    @Test func anUninstalledFontIsForgotten() {
        let (defaults, folder) = fresh()
        defaults.set("Some Font Nobody Has", forKey: "fontFamily")
        #expect(Appearance(defaults: defaults, folder: folder, installedFamilies: { ["Avenir"] }).fontFamily == nil)
    }

    @Test func theAppIconIsInkUntilAnotherIsChosenAndThenKept() {
        let (defaults, folder) = fresh()
        let a = Appearance(defaults: defaults, folder: folder)
        #expect(a.appIcon == .ink)
        #expect(a.appIcon.isDefault)
        a.appIcon = .plum
        #expect(Appearance(defaults: defaults, folder: folder).appIcon == .plum)
        defaults.set("a colour from a later version", forKey: "appIcon")
        #expect(Appearance(defaults: defaults, folder: folder).appIcon == .ink)
    }

    /// The names match the variants scripts/generate-app-icon.sh compiles from xBot.icon.
    @Test func everyAppIconHasAResourceName() {
        #expect(Appearance.AppIcon.allCases.map(\.rawValue) == ["ink", "rose", "sunset", "plum"])
    }
}

