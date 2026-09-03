import AppKit
import Foundation

public enum DiagnosticsClipboard {
    public static func copy(_ diagnostics: Diagnostics) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics.rendered(), forType: .string)
    }
}
