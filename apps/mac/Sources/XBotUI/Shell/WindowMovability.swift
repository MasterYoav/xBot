import AppKit
import SwiftUI

extension View {
    /**
     The window moves only where the app says it may: the empty parts of the top bar, the sidebar's
     header and the files column's header, each of which carries a `WindowDragGesture`.

     Left to itself, AppKit moves a hidden-title-bar window from any press-and-drag in the title-bar
     row. That row is the tab strip, so dragging a tab to reorder it dragged the whole window
     instead, and the tab never saw the pointer move.
     */
    public func windowMovesOnlyFromDragAreas() -> some View {
        background(WindowMovability())
    }
}

private struct WindowMovability: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isMovable = false
        }
    }
}
