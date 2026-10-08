import SwiftUI

/// A symbol and tint for a file or folder, by its name.
enum FileIcon {
    static func symbol(for name: String, isFolder: Bool) -> String {
        if isFolder {
            return switch name {
            case ".git": "arrow.triangle.branch"
            case ".github": "gearshape.2"
            case "docs", "Docs": "book.closed"
            case "apps", "Sources", "src": "shippingbox"
            case "assets", "Resources": "photo.on.rectangle"
            case "scripts": "terminal"
            case "site", "web": "globe"
            case "Tests", "tests": "checkmark.seal"
            default: "folder"
            }
        }
        switch (name as NSString).pathExtension.lowercased() {
        case "swift": return "swift"
        case "md", "markdown", "txt": return "doc.text"
        case "json", "yml", "yaml", "toml", "plist": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "heic", "svg", "icns": return "photo"
        case "key", "pem", "p12": return "key"
        case "sh", "zsh", "bash": return "terminal"
        default: break
        }
        return switch name.lowercased() {
        case "license", "licence", "notice": "checkmark.shield"
        case ".gitignore", ".gitattributes": "eye.slash"
        default: "doc"
        }
    }

    static func tint(for name: String, isFolder: Bool) -> Color {
        if isFolder { return name == ".git" || name == ".github" ? Palette.accent : Palette.textSecondary }
        return (name as NSString).pathExtension == "swift" ? Palette.warning : Palette.textTertiary
    }
}
