import AppKit
import SwiftUI

/// Translucency as a functional layer. Weight encodes hierarchy: heavier separates structural
/// regions, lighter draws attention to interactive ones.
public enum Materials {
    /// Fraction of the aurora that shows through frosted chrome. 0.6 = 60% transparent.
    public static let frostedTransparency: CGFloat = 0.6

    public static let popover = Material.thick
    public static let overlayPill = Material.ultraThin
}

/// Frosted glass backed by `NSVisualEffectView`, tuned for the aurora field beneath.
public struct FrostedGlassBackground: View {
    private let material: NSVisualEffectView.Material

    public init(material: NSVisualEffectView.Material = .sidebar) {
        self.material = material
    }

    public var body: some View {
        VisualEffectView(material: material, alpha: 1 - Materials.frostedTransparency)
    }
}

extension View {
    /// A SwiftUI material that becomes an opaque fill under Reduce Transparency.
    public func xbotMaterial(_ material: Material, opaqueFallback: Color) -> some View {
        modifier(SwiftUIMaterialModifier(material: material, opaqueFallback: opaqueFallback))
    }

    /// ~60% transparent frosted glass. Opaque under Reduce Transparency.
    public func frostedGlass(
        material: NSVisualEffectView.Material = .sidebar,
        opaqueFallback: Color
    ) -> some View {
        modifier(FrostedGlassModifier(material: material, opaqueFallback: opaqueFallback))
    }
}

private struct SwiftUIMaterialModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let material: Material
    let opaqueFallback: Color

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(opaqueFallback)
        } else {
            content.background(material)
        }
    }
}

private struct FrostedGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let material: NSVisualEffectView.Material
    let opaqueFallback: Color

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(opaqueFallback)
        } else {
            content.background(FrostedGlassBackground(material: material))
        }
    }
}

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let alpha: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = alpha
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.alphaValue = alpha
    }
}
