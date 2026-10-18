import ApplicationServices
import CoreGraphics
import Foundation

/// Accessibility and Screen Recording, which Mac control needs. Both are granted only in System
/// Settings › Privacy & Security, so the app opens the floating guide there; these are the live
/// checks it watches. macOS asks about the app itself: the debug binary started from a terminal
/// is judged as that terminal.
public enum MacControlAccess {
    public static func isAllowed(_ permission: MacPermission) -> Bool {
        switch permission {
        case .accessibility: AXIsProcessTrusted()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        }
    }

    /// macOS's own prompt, which adds xBot to the list (switched off) so the person only has to
    /// turn it on.
    public static func request(_ permission: MacPermission) {
        switch permission {
        case .accessibility:
            // kAXTrustedCheckOptionPrompt's value, spelled out: the global is a mutable C var.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
    }

    /// The pane in System Settings where it's switched on.
    public static func settingsURL(_ permission: MacPermission) -> URL {
        switch permission {
        case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        }
    }

    /// Checks once a second while `keepWaiting` says so. True once allowed.
    @MainActor
    public static func waitUntilAllowed(_ permission: MacPermission, while keepWaiting: @MainActor () -> Bool) async -> Bool {
        while keepWaiting() {
            if isAllowed(permission) { return true }
            try? await Task.sleep(for: .seconds(1))
        }
        return isAllowed(permission)
    }
}
