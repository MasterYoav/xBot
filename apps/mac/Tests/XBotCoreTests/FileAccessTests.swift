import Foundation
import Testing
@testable import XBotCore

/// A Mac whose answers the test decides.
final class ScriptedFiles: FileAccessProbe, @unchecked Sendable {
    private let lock = NSLock()
    private var _answers: [ProtectedFolder: Bool] = [:]
    private var _reads: [ProtectedFolder] = []
    private var _fdaChecks = 0
    /// Full Disk Access arrives on this check (nil: never).
    var fdaOnCheck: Int?

    var answers: [ProtectedFolder: Bool] {
        get { lock.withLock { _answers } }
        set { lock.withLock { _answers = newValue } }
    }
    var reads: [ProtectedFolder] { lock.withLock { _reads } }
    var fdaChecks: Int { lock.withLock { _fdaChecks } }

    func canRead(_ folder: ProtectedFolder) -> Bool {
        lock.withLock {
            _reads.append(folder)
            return _answers[folder] ?? false
        }
    }

    func hasFullDiskAccess() -> Bool {
        lock.withLock {
            _fdaChecks += 1
            return fdaOnCheck.map { _fdaChecks >= $0 } ?? false
        }
    }
}

@MainActor @Suite struct FileAccessTests {
    func defaults() -> UserDefaults { UserDefaults(suiteName: "files-\(UUID().uuidString)")! }

    /// Reading a folder nobody has asked about yet would raise macOS's prompt on its own: the step
    /// appearing must not do that.
    @Test func showingTheStepNeverPrompts() async {
        let probe = ScriptedFiles()
        let access = FileAccess(probe: probe, defaults: defaults())
        await access.refresh()
        #expect(probe.reads.isEmpty)
        #expect(ProtectedFolder.allCases.allSatisfy { access.state(of: $0) == .unknown })
        #expect(!access.fullDiskAccess)
    }

    @Test func allowReadsTheFolderOnceAndRecordsTheAnswer() async {
        let probe = ScriptedFiles()
        probe.answers = [.desktop: true, .documents: false]
        let store = defaults()
        let access = FileAccess(probe: probe, defaults: store)
        await access.request(.desktop)
        await access.request(.documents)
        #expect(access.state(of: .desktop) == .allowed)
        #expect(access.state(of: .documents) == .denied)
        #expect(access.state(of: .downloads) == .unknown)
        #expect(probe.reads == [.desktop, .documents])

        // Later (another launch), folders asked about before are read again for the truth.
        probe.answers = [.desktop: false, .documents: true]
        let later = FileAccess(probe: probe, defaults: store)
        await later.refresh()
        #expect(later.state(of: .desktop) == .denied)
        #expect(later.state(of: .documents) == .allowed)
        #expect(later.state(of: .downloads) == .unknown)
        #expect(!probe.reads.dropFirst(2).contains(.downloads))
    }

    @Test func fullDiskAccessCoversEveryFolderWithoutReadingThem() async {
        let probe = ScriptedFiles()
        probe.fdaOnCheck = 1
        let access = FileAccess(probe: probe, defaults: defaults())
        await access.refresh()
        #expect(access.fullDiskAccess)
        #expect(ProtectedFolder.allCases.allSatisfy { access.state(of: $0) == .allowed })
        #expect(probe.reads.isEmpty)
        #expect(access.allAllowed)
    }

    @Test func allowAllAsksOneFolderAfterAnotherSkippingTheAllowed() async {
        let probe = ScriptedFiles()
        probe.answers = [.desktop: true, .documents: true, .downloads: true]
        let access = FileAccess(probe: probe, defaults: defaults())
        await access.request(.documents)
        await access.requestAll()
        #expect(probe.reads == [.documents, .desktop, .downloads])
        #expect(access.allAllowed)
    }

    @Test func waitingStopsWhenFullDiskAccessArrives() async {
        let probe = ScriptedFiles()
        probe.fdaOnCheck = 3
        let access = FileAccess(probe: probe, defaults: defaults())
        let granted = await access.waitForFullDiskAccess(every: .milliseconds(5))
        #expect(granted)
        #expect(access.fullDiskAccess)
        #expect(probe.fdaChecks == 3)
        #expect(ProtectedFolder.allCases.allSatisfy { access.state(of: $0) == .allowed })
    }

    @Test func waitingStopsWhenThePanelCloses() async {
        let probe = ScriptedFiles()
        let access = FileAccess(probe: probe, defaults: defaults())
        var checks = 0
        let granted = await access.waitForFullDiskAccess(every: .milliseconds(5), while: {
            checks += 1
            return checks < 4
        })
        #expect(!granted)
        #expect(!access.fullDiskAccess)
        #expect(probe.fdaChecks <= 4)
    }

    @Test func waitingStopsWhenCancelled() async {
        let probe = ScriptedFiles()
        let access = FileAccess(probe: probe, defaults: defaults())
        let wait = Task { await access.waitForFullDiskAccess(every: .milliseconds(20)) }
        try? await Task.sleep(for: .milliseconds(100))
        wait.cancel()
        let granted = await wait.value
        #expect(!granted)
        let checks = probe.fdaChecks
        try? await Task.sleep(for: .milliseconds(150))
        #expect(probe.fdaChecks == checks)
    }

    @Test func theFoldersAreInTheHomeFolder() {
        let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
        #expect(ProtectedFolder.desktop.url(home: home).path == "/Users/me/Desktop")
        #expect(ProtectedFolder.documents.url(home: home).path == "/Users/me/Documents")
        #expect(ProtectedFolder.downloads.url(home: home).path == "/Users/me/Downloads")
        #expect(FileAccess.fullDiskAccessSettings.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }
}
