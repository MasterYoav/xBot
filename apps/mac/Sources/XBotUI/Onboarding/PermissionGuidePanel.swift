import AppKit
import SwiftUI
import XBotCore

/// Full Disk Access, Accessibility and Screen Recording are granted only in System Settings, so the
/// help goes there: a small floating panel that docks beside the System Settings window and
/// follows it, with xBot's icon to drag into the list and a switch showing what to turn on. It
/// checks the grant every second while it's up; when it flips, it shows a check, closes, and
/// brings xBot back to the front.
@MainActor
final class PermissionGuide {
    static let shared = PermissionGuide()

    /// One permission the guide can walk through: where it is, what the list is called, and the
    /// live check that says it's on.
    struct Topic {
        var settingsURL: URL
        /// The list's name in System Settings: "Full Disk Access".
        var listName: String
        /// Waits while the closure says so; true once granted.
        var waitForGrant: @MainActor (_ keepWaiting: @escaping @MainActor () -> Bool) async -> Bool

        @MainActor static func fullDiskAccess(_ files: FileAccess) -> Topic {
            Topic(settingsURL: FileAccess.fullDiskAccessSettings, listName: String(localized: "Full Disk Access")) { keepWaiting in
                await files.waitForFullDiskAccess(while: keepWaiting)
            }
        }

        @MainActor static func mac(_ permission: MacPermission) -> Topic {
            let name = switch permission {
            case .accessibility: String(localized: "Accessibility")
            case .screenRecording: String(localized: "Screen Recording")
            }
            return Topic(settingsURL: MacControlAccess.settingsURL(permission), listName: name) { keepWaiting in
                await MacControlAccess.waitUntilAllowed(permission, while: keepWaiting)
            }
        }
    }

    private var panel: NSPanel?
    private let state = GuideState()
    private var docking: Task<Void, Never>?
    private var waiting: Task<Void, Never>?
    private var closeObserver: NSObjectProtocol?
    /// When System Settings was last seen running. It takes a moment to start.
    private var settingsSeen = Date.now

    func show(files: FileAccess) { show(.fullDiskAccess(files)) }

    func show(_ topic: Topic) {
        NSWorkspace.shared.open(topic.settingsURL)
        let panel = panel ?? makePanel()
        self.panel = panel
        state.granted = false
        state.listName = topic.listName
        settingsSeen = .now
        panel.orderFrontRegardless()

        docking?.cancel()
        docking = Task { [weak self] in
            while !Task.isCancelled {
                self?.dock()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        waiting?.cancel()
        waiting = Task { [weak self] in
            let granted = await topic.waitForGrant({ self?.panel?.isVisible == true })
            if granted { await self?.succeed() }
        }
    }

    func close() {
        docking?.cancel()
        waiting?.cancel()
        docking = nil
        waiting = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func succeed() async {
        state.granted = true
        try? await Task.sleep(for: .seconds(1.2))
        close()
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain && $0.isVisible }?.makeKeyAndOrderFront(nil)
    }

    /// Beside System Settings' window, wherever it is. If System Settings has quit, the guide goes
    /// too, and the step stays as it was.
    private func dock() {
        guard let panel else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: GuideDock.settingsBundleID)
        guard !running.isEmpty else {
            if Date.now.timeIntervalSince(settingsSeen) > 5 { close() }
            return
        }
        settingsSeen = .now
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        guard let found = GuideDock.settingsWindow(in: list, pids: Set(running.map(\.processIdentifier))),
              let main = NSScreen.screens.first else { return }
        let window = GuideDock.cocoaRect(fromWindowList: found, mainScreenHeight: main.frame.height)
        let screen = NSScreen.screens.first { $0.frame.intersects(window) } ?? main
        let origin = GuideDock.origin(beside: window, panel: panel.frame.size, screen: screen.visibleFrame)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Metrics.guidePanel),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        // xBot isn't the active app while the person is in System Settings.
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Close only: there's nothing to minimise or zoom.
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: GuideContent(state: state))
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.close() } }
        return panel
    }
}

@MainActor @Observable
final class GuideState {
    var granted = false
    var listName = String(localized: "Full Disk Access")
}

/// The guide for Mac control's permissions, for the app to open when a tool needs one.
public enum MacPermissionGuide {
    @MainActor public static func show(_ permission: MacPermission) {
        // macOS's own prompt first: it puts xBot in the list, so the person only turns it on.
        MacControlAccess.request(permission)
        PermissionGuide.shared.show(.mac(permission))
    }
}

/// Where the guide goes. Pure geometry, so it's tested.
enum GuideDock {
    static let settingsBundleID = "com.apple.systempreferences"
    /// From System Settings' window.
    static let gap: CGFloat = Space.m
    /// Below System Settings' title bar and search field.
    static let topInset: CGFloat = Space.xxl + Space.xl

    /// The window list measures from the top-left of the main screen; AppKit from its bottom-left.
    static func cocoaRect(fromWindowList rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// To the right of the window, near its top; to the left when the right has no room; always on
    /// the screen.
    static func origin(beside window: CGRect, panel: CGSize, screen: CGRect) -> CGPoint {
        var x = window.maxX + gap
        if x + panel.width > screen.maxX { x = window.minX - gap - panel.width }
        let y = window.maxY - topInset - panel.height
        return CGPoint(x: min(max(x, screen.minX), screen.maxX - panel.width),
                       y: min(max(y, screen.minY), screen.maxY - panel.height))
    }

    /// System Settings' main window: a normal-level window of its process (by pid when known, else
    /// by name), the largest if it has several. The window list gives owners and bounds without the
    /// Screen Recording permission (only window titles need it).
    static func settingsWindow(in list: [[String: Any]], pids: Set<pid_t>? = nil) -> CGRect? {
        list.compactMap { info -> CGRect? in
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            if let pids {
                guard let pid = info[kCGWindowOwnerPID as String] as? Int, pids.contains(pid_t(pid)) else { return nil }
            } else {
                guard (info[kCGWindowOwnerName as String] as? String) == "System Settings" else { return nil }
            }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return rect
        }
        .max { $0.width * $0.height < $1.width * $1.height }
    }
}

/// The panel's face: xBot's icon to drag into the list, a switch turning on, one line.
private struct GuideContent: View {
    let state: GuideState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var icon: NSImage { NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath) }

    var body: some View {
        VStack(spacing: Space.m) {
            if state.granted {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(Typography.hero)
                    .imageScale(.large)
                    .foregroundStyle(Palette.success)
                    .transition(.scale.combined(with: .opacity))
                Text(String(localized: "\(state.listName) is on.")).titleText()
                Spacer()
            } else {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: Metrics.guideIcon, height: Metrics.guideIcon)
                    // The app itself, as a file: dropped on the permission's list it adds xBot.
                    .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                    .help(String(localized: "Drag into the list"))
                    .accessibilityLabel(String(localized: "xBot. Drag into the \(state.listName) list."))
                Text(String(localized: "Drag into the list")).labelText().foregroundStyle(Palette.textTertiary)
                HStack(spacing: Space.s) {
                    Image(nsImage: icon).resizable().frame(width: Space.l + Space.xs, height: Space.l + Space.xs)
                    Text(String(localized: "xBot")).emphasisText()
                    Spacer()
                    GuideSwitch(animated: !reduceMotion)
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .raisedSurface(radius: Radius.medium)
                Text(String(localized: "Turn xBot on under \(state.listName). Not in the list? Drag the icon above into it."))
                    .captionText()
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.l)
        .padding(.top, Space.s)
        .frame(width: Metrics.guidePanel.width, height: Metrics.guidePanel.height)
        .background(Palette.window)
        .motion(Motion.standard, value: state.granted)
    }
}

/// A switch that flips on, pauses, and starts again. Under Reduce Motion it simply shows on.
private struct GuideSwitch: View {
    let animated: Bool

    var body: some View {
        if animated {
            Capsule().fill(.clear)
                .frame(width: Metrics.guideSwitch.width, height: Metrics.guideSwitch.height)
                .phaseAnimator([false, true]) { _, on in
                    track(on: on)
                } animation: { on in
                    on ? Motion.standard.delay(0.8) : Motion.quick.delay(1.6)
                }
                .accessibilityHidden(true)
        } else {
            track(on: true).accessibilityHidden(true)
        }
    }

    private func track(on: Bool) -> some View {
        Capsule()
            .fill(on ? Palette.success : Palette.hover)
            .overlay(Capsule().strokeBorder(Palette.hairline))
            .frame(width: Metrics.guideSwitch.width, height: Metrics.guideSwitch.height)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(Palette.knob).padding(Space.xxs).cardShadow()
            }
    }
}
