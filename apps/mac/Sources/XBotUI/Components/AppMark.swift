import AppKit
import SwiftUI

/// The official xBot mark — compiled from `xBot.icon` via actool (`xBot.icns`).
public enum AppMark {
    private static let resourceName = "xBot"

    public static var image: NSImage? {
        if let url = Bundle.module.url(forResource: resourceName, withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: resourceName)
    }

    /// Applies the Dock icon when running outside a fully bundled .app (e.g. `swift run`).
    @MainActor
    public static func applyDockIcon() {
        NSApplication.shared.applicationIconImage = image
    }
}

public struct AppMarkView: View {
    private let size: CGFloat

    public init(size: CGFloat = 72) {
        self.size = size
    }

    public var body: some View {
        Group {
            if let image = AppMark.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(String(localized: "xBot"))
    }
}
