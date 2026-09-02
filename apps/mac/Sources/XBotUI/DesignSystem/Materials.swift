import SwiftUI

/// Translucency as a functional layer. Weight encodes hierarchy: heavier separates structural
/// regions, lighter draws attention to interactive ones.
public enum Materials {
    public static let rail = Material.bar
    public static let panel = Material.regular
    public static let popover = Material.thick
    public static let overlayPill = Material.ultraThin
}

extension View {
    /// A material that becomes an opaque fill under Reduce Transparency.
    ///
    /// In the component, not at the call site — same reason as `motion`. A view asks for a material
    /// and gets the right thing; it never reads the environment flag itself, so it cannot forget to.
    public func xbotMaterial(_ material: Material, opaqueFallback: Color) -> some View {
        modifier(MaterialModifier(material: material, opaqueFallback: opaqueFallback))
    }
}

private struct MaterialModifier: ViewModifier {
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
