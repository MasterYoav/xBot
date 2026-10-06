import AppKit
import SwiftUI
import XBotCore
import XBotUI

@main
struct XBotApp: App {
    private let appUpdates = SparkleAppUpdateController()

    var body: some Scene {
        Window("xBot", id: "main") {
            Text(verbatim: "xBot")
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "About xBot")) { AboutPanel.show() }
            }
            CommandGroup(after: .appInfo) {
                Button(String(localized: "Check for Updates…")) {
                    appUpdates.checkForUpdates(userInitiated: true)
                }
            }
            CommandGroup(replacing: .help) {
                Button(String(localized: "xBot Documentation")) {
                    NSWorkspace.shared.open(AboutPanel.documentationURL)
                }
            }
        }
    }
}
