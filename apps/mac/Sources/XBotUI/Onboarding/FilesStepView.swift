import AppKit
import SwiftUI
import XBotCore

/// Step 8: Desktop, Documents and Downloads, each allowed from here, so macOS's prompt comes up in
/// front of the tour instead of in the middle of an agent's work; or Full Disk Access, with a
/// guide beside System Settings.
struct FilesStepView: View {
    let files: FileAccess

    var body: some View {
        StepPage(copy: .of(.files)) {
            FilesScene()
        } controls: {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(ProtectedFolder.allCases, id: \.self) { folder in row(folder) }
                Divider().padding(.vertical, Space.xs)
                if files.fullDiskAccess {
                    Label(String(localized: "xBot has Full Disk Access."), systemImage: "checkmark.shield.fill")
                        .captionText().foregroundStyle(Palette.success)
                } else {
                    HStack(spacing: Space.s) {
                        if !files.allAllowed {
                            Button(String(localized: "Allow all")) { Task { await files.requestAll() } }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(files.requesting != nil)
                        }
                        Button(String(localized: "Or give Full Disk Access…")) { PermissionGuide.shared.show(files: files) }
                            .buttonStyle(QuietButtonStyle())
                            .help(String(localized: "One switch in System Settings that covers every folder."))
                    }
                }
            }
        }
        // The truth each time the step appears: a grant changed in System Settings shows here.
        .task { await files.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await files.refresh() }
        }
    }

    private func row(_ folder: ProtectedFolder) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: folder.symbol)
                .font(Typography.emphasis)
                .foregroundStyle(tint(folder))
                .frame(width: Metrics.iconButton, height: Metrics.iconButton)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(folder.title).emphasisText()
                Text(caption(folder)).captionText().foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            switch files.state(of: folder) {
            case .allowed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success)
                    .accessibilityLabel(String(localized: "Allowed"))
            case .denied:
                Button(String(localized: "Open Settings")) { NSWorkspace.shared.open(FileAccess.filesAndFoldersSettings) }
                    .buttonStyle(QuietButtonStyle())
            case .unknown:
                if files.requesting == folder {
                    ProgressView().controlSize(.small)
                } else {
                    Button(String(localized: "Allow")) { Task { await files.request(folder) } }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(files.requesting != nil)
                        .accessibilityLabel(String(localized: "Allow \(folder.title)"))
                }
            }
        }
        .motion(Motion.quick, value: files.state(of: folder))
    }

    private func tint(_ folder: ProtectedFolder) -> Color {
        switch files.state(of: folder) {
        case .allowed: Palette.success
        case .denied: Palette.failure
        case .unknown: Palette.textSecondary
        }
    }

    private func caption(_ folder: ProtectedFolder) -> String {
        switch files.state(of: folder) {
        case .allowed: String(localized: "Allowed")
        case .denied: String(localized: "Not allowed: change it in System Settings.")
        case .unknown: files.requesting == folder ? String(localized: "macOS is asking…") : String(localized: "Not asked yet")
        }
    }
}
