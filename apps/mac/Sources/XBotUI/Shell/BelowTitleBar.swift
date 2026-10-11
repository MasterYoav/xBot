import SwiftUI

extension View {
    /**
     Content that starts under the title bar row, kept from growing up into it.

     A SwiftUI `ScrollView` whose top edge lands exactly on the window's title-bar safe area is
     stretched up into it, so its edge effect can run under the bar. Here the bar is our own top
     bar, drawn in the content, and the stretched scroll view — an AppKit view above it — took every
     click meant for it: inside a chat, the files-and-changes toggle, "+", Show sidebar, a tab's ×
     and the column's Explorer / Changes tabs all did nothing. One point of space keeps the edges
     apart, which is all it takes; it sits under the bar's own hairline-free bottom and is not seen.
     */
    func belowTitleBar() -> some View {
        padding(.top, 1)
    }
}
