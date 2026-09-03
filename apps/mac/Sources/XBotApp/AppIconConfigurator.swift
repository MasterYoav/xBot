import AppKit
import XBotUI

enum AppIconConfigurator {
    @MainActor
    static func apply() {
        AppMark.applyDockIcon()
    }
}
