import AppKit
import SwiftUI

/// Window chrome: main window uses a frosted unified toolbar; onboarding is fully transparent.
public struct WindowChromeConfigurator: NSViewRepresentable {
    public enum Style {
        case main
        case onboarding
    }

    var style: Style = .main

    public init(style: Style = .main) {
        self.style = style
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(window: view.window) }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(window: nsView.window) }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        switch style {
        case .main:
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarSeparatorStyle = .none
            if #available(macOS 15.0, *) {
                window.toolbarStyle = .unifiedCompact
            }
            window.toolbar?.showsBaselineSeparator = false
            window.toolbar?.items.forEach { $0.isBordered = false }
            stripToolbarItemBackgrounds(in: window.contentView)
            clearTitlebarBackground(in: window)
        case .onboarding:
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarSeparatorStyle = .none
            if #available(macOS 15.0, *) {
                window.toolbarStyle = .unifiedCompact
            }
            stripToolbarItemBackgrounds(in: window.contentView)
            clearTitlebarBackground(in: window)
        }
    }

    private func stripToolbarItemBackgrounds(in view: NSView?) {
        guard let view else { return }
        let className = String(describing: type(of: view))
        if className.contains("Toolbar") && className.contains("Background") {
            view.isHidden = true
        }
        for child in view.subviews {
            stripToolbarItemBackgrounds(in: child)
        }
    }

    /// The opaque strip above onboarding content — hide it so the aurora reaches the traffic lights.
    private func clearTitlebarBackground(in window: NSWindow) {
        guard var view = window.contentView?.superview else { return }
        while true {
            let name = String(describing: type(of: view))
            if name.contains("Titlebar") || name.contains("ThemeWidget") {
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.clear.cgColor
            }
            guard let superview = view.superview else { break }
            view = superview
        }
    }
}
