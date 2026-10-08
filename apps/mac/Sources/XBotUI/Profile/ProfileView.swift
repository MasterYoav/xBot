import SwiftUI
import XBotCore

struct ProfileView: View {
    let workspace: Workspace

    var body: some View {
        Text(String(localized: "Profile")).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
