import AppKit
import Foundation

/// Launch the container runtime without asking the user to open Terminal.
public enum RuntimeLauncher: Sendable {
    public static func openDockerDesktop() {
        let candidates = [
            "/Applications/Docker.app",
            "\(NSHomeDirectory())/Applications/Docker.app",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }
    }

    public static func openDockerDownloadPage() {
        guard let url = URL(string: "https://www.docker.com/products/docker-desktop/") else { return }
        NSWorkspace.shared.open(url)
    }

    public static func openStorageSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
