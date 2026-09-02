import SwiftUI
import XBotCore

/// Rail, conversation, panel. The panel arrives with M5; the two regions that exist are the two
/// the product is unusable without.
public struct MainWindow: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            Rail()
            Conversation()
        }
        .frame(
            minWidth: Metrics.minimumWindow.width,
            minHeight: Metrics.minimumWindow.height
        )
        .task { await state.load() }
    }
}
