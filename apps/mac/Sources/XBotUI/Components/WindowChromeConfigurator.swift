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
        let view = ChromeHost()
        view.configure = { window in configure(window: window) }
        DispatchQueue.main.async { [weak view] in view?.applyChrome() }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let host = nsView as? ChromeHost else { return }
        host.configure = { window in configure(window: window) }
        DispatchQueue.main.async { [weak host] in host?.applyChrome() }
    }

    /// Re-applies the chrome whenever AppKit rebuilds the title bar.
    ///
    /// One `DispatchQueue.main.async` from `makeNSView` was not enough. On a cold launch the
    /// toolbar's item background views do not exist yet when it runs, so the walk that hides them
    /// finds nothing — and the app opened with a glass pill behind each toggle and behind the agent
    /// name. Pressing any toggle drove `updateNSView`, by which time the views existed, and they
    /// vanished. The chrome was correct only after the person touched something.
    ///
    /// `didUpdateNotification` is the deterministic hook rather than a longer delay: AppKit posts it
    /// when the window has finished updating, including the pass that first builds the toolbar, and
    /// again after anything that rebuilds it — entering full screen, or a toolbar item changing.
    /// Hiding an already-hidden view is a no-op, so re-running it costs a short tree walk.
    final class ChromeHost: NSView {
        var configure: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            NotificationCenter.default.removeObserver(self)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidUpdate),
                name: NSWindow.didUpdateNotification,
                object: window
            )
            applyChrome()
        }

        @objc private func windowDidUpdate() {
            applyChrome()
        }

        func applyChrome() {
            configure?(window)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
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
