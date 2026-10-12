import SwiftUI
import UIKit

/// The app's one colour, chosen in Settings › Appearance. Every view reads `Theme.accent`, which
/// reads this; Observation redraws them when it changes.
@MainActor @Observable
final class AccentStore {
    static let shared = AccentStore()
    private static let key = "accent"

    /// "#RRGGBB".
    var hex: String {
        didSet { UserDefaults.standard.set(hex, forKey: Self.key) }
    }

    private init() { hex = UserDefaults.standard.string(forKey: Self.key) ?? AccentChoice.presets[0].hex }

    var color: Color { Color(hexString: hex) }
}

struct AccentChoice: Identifiable, Hashable {
    let name: String
    let hex: String
    var id: String { hex }

    static let presets: [AccentChoice] = [
        AccentChoice(name: String(localized: "Orchid"), hex: "#B55E8C"),
        AccentChoice(name: String(localized: "Violet"), hex: "#7C5CE6"),
        AccentChoice(name: String(localized: "Blue"), hex: "#2F7CF6"),
        AccentChoice(name: String(localized: "Teal"), hex: "#14A3A3"),
        AccentChoice(name: String(localized: "Green"), hex: "#2FA866"),
        AccentChoice(name: String(localized: "Amber"), hex: "#E39A1F"),
        AccentChoice(name: String(localized: "Coral"), hex: "#E5604D"),
        AccentChoice(name: String(localized: "Graphite"), hex: "#6E7280"),
    ]
}

extension Color {
    init(hexString: String) {
        let digits = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(digits, radix: 16) ?? 0xB55E8C
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    /// "#RRGGBB" for this colour.
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    /// The same hue, lighter and brighter: for glows.
    func brighter(_ amount: CGFloat = 0.25) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: max(s - amount * 0.3, 0), brightness: min(b + amount, 1))
    }

    /// The hue turned a little: a second colour for gradients.
    func turned(_ degrees: CGFloat) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var hue = h + degrees / 360
        hue -= floor(hue)
        return Color(hue: hue, saturation: s, brightness: b)
    }
}

/// Each AI provider's own colours, so a glance tells them apart.
struct ProviderStyle {
    let primary: Color
    let secondary: Color
    let name: String

    var gradient: LinearGradient { LinearGradient(colors: [secondary, primary], startPoint: .topLeading, endPoint: .bottomTrailing) }
    var angular: AngularGradient { AngularGradient(colors: [secondary, primary, primary], center: .center) }

    private static func hue(_ id: String) -> Double {
        Double(id.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
    }

    static func of(_ id: String, name: String? = nil) -> ProviderStyle {
        return switch id {
        case "claude": ProviderStyle(primary: Color(hexString: "#D97757"), secondary: Color(hexString: "#F4B39A"), name: name ?? "Claude")
        case "codex", "openai": ProviderStyle(primary: Color(hexString: "#10A37F"), secondary: Color(hexString: "#6FE3C3"), name: name ?? "Codex")
        case "antigravity", "gemini": ProviderStyle(primary: Color(hexString: "#4285F4"), secondary: Color(hexString: "#9B72F2"), name: name ?? "Antigravity")
        case "copilot": ProviderStyle(primary: Color(hexString: "#8957E5"), secondary: Color(hexString: "#E06BD0"), name: name ?? "Copilot")
        case "cursor": ProviderStyle(primary: Color(hexString: "#5C6BC0"), secondary: Color(hexString: "#A5B4FC"), name: name ?? "Cursor")
        case "opencode": ProviderStyle(primary: Color(hexString: "#F59E0B"), secondary: Color(hexString: "#FCD34D"), name: name ?? "OpenCode")
        case "grok", "xai": ProviderStyle(primary: Color(hexString: "#9CA3AF"), secondary: Color(hexString: "#F3F4F6"), name: name ?? "Grok")
        case "mistral": ProviderStyle(primary: Color(hexString: "#FA520F"), secondary: Color(hexString: "#FFB000"), name: name ?? "Mistral")
        default:
            // Anyone else: a stable hue of their own.
            ProviderStyle(primary: Color(hue: hue(id), saturation: 0.65, brightness: 0.85),
                                 secondary: Color(hue: hue(id), saturation: 0.35, brightness: 1), name: name ?? id.capitalized)
        }
    }
}
