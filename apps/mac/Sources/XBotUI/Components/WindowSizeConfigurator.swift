import AppKit
import SwiftUI

/// Resizes the hosting window when onboarding hands off to the main app.
public struct WindowSizeConfigurator: NSViewRepresentable {
    var contentSize: CGSize
    var resizable: Bool

    public init(contentSize: CGSize, resizable: Bool) {
        self.contentSize = contentSize
        self.resizable = resizable
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.setContentSize(contentSize)
        window.styleMask.insert(.titled, if: resizable)
        if !resizable {
            window.styleMask.remove(.resizable)
        } else {
            window.styleMask.insert(.resizable)
        }
        window.center()
    }
}

private extension NSWindow.StyleMask {
    mutating func insert(_ mask: NSWindow.StyleMask, if condition: Bool) {
        if condition { insert(mask) }
    }
}
