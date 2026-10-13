import Foundation
import Observation

/// The folders macOS asks about the first time an app's process touches them.
public enum ProtectedFolder: String, CaseIterable, Sendable {
    case desktop, documents, downloads

    /// Finder's names, which macOS localises itself.
    public var title: String {
        switch self {
        case .desktop: String(localized: "Desktop")
        case .documents: String(localized: "Documents")
        case .downloads: String(localized: "Downloads")
        }
    }

    public var symbol: String {
        switch self {
        case .desktop: "menubar.dock.rectangle"
        case .documents: "doc.text"
        case .downloads: "arrow.down.circle"
        }
    }

    public func url(home: URL) -> URL {
        switch self {
        case .desktop: home.appending(path: "Desktop", directoryHint: .isDirectory)
        case .documents: home.appending(path: "Documents", directoryHint: .isDirectory)
        case .downloads: home.appending(path: "Downloads", directoryHint: .isDirectory)
        }
    }
}

public enum FolderAccess: Equatable, Sendable {
    /// Never asked: finding out would raise the prompt.
    case unknown, allowed, denied
}

/// How FileAccess touches the disk. Scripted in tests.
public protocol FileAccessProbe: Sendable {
    /// Lists the folder once, from this process. The first time, macOS asks the person (and this
    /// waits for the answer); afterwards it answers from what they chose.
    func canRead(_ folder: ProtectedFolder) -> Bool
    /// A read that only succeeds with Full Disk Access, and never prompts.
    func hasFullDiskAccess() -> Bool
}

/// The files step: Desktop, Documents and Downloads, or Full Disk Access, asked for up front so an
/// agent turn never stops mid-task on a prompt.
@MainActor
@Observable
public final class FileAccess {
    /// Privacy & Security › Full Disk Access.
    public static let fullDiskAccessSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    /// Privacy & Security › Files & Folders, where a refused folder is changed.
    public static let filesAndFoldersSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!

    public private(set) var folders: [ProtectedFolder: FolderAccess] = [:]
    public private(set) var fullDiskAccess = false
    /// The folder whose prompt is up.
    public private(set) var requesting: ProtectedFolder?

    @ObservationIgnored private let probe: any FileAccessProbe
    @ObservationIgnored private let defaults: UserDefaults
    private static let askedKey = "onboarding.foldersAsked"

    public init(probe: any FileAccessProbe = LiveFileAccessProbe(), defaults: UserDefaults = .standard) {
        self.probe = probe
        self.defaults = defaults
    }

    public func state(of folder: ProtectedFolder) -> FolderAccess { folders[folder] ?? .unknown }

    public var allAllowed: Bool { ProtectedFolder.allCases.allSatisfy { state(of: $0) == .allowed } }

    /// The truth, whenever the step appears: Full Disk Access, and each folder already asked about.
    /// A folder never asked about stays unknown, because reading it would prompt.
    public func refresh() async {
        let probe = probe
        if await Task.detached(operation: { probe.hasFullDiskAccess() }).value {
            grantAll()
            return
        }
        fullDiskAccess = false
        let asked = askedFolders
        for folder in ProtectedFolder.allCases {
            guard asked.contains(folder) else {
                folders[folder] = .unknown
                continue
            }
            folders[folder] = await read(folder) ? .allowed : .denied
        }
    }

    /// Allow: reads the folder from xBot itself, so macOS shows its prompt now, in front of the
    /// onboarding window.
    public func request(_ folder: ProtectedFolder) async {
        guard requesting == nil else { return }
        requesting = folder
        defer { requesting = nil }
        var asked = askedFolders
        asked.insert(folder)
        defaults.set(asked.map(\.rawValue).sorted(), forKey: Self.askedKey)
        folders[folder] = await read(folder) ? .allowed : .denied
    }

    /// Each folder not yet allowed, one prompt after another.
    public func requestAll() async {
        for folder in ProtectedFolder.allCases where state(of: folder) != .allowed {
            await request(folder)
        }
    }

    /// Checks for Full Disk Access every `interval` while the guide panel is up: true as soon as it's
    /// granted, false when `keepWaiting` says stop (the panel closed) or the task is cancelled.
    public func waitForFullDiskAccess(
        every interval: Duration = .seconds(1), while keepWaiting: @MainActor () -> Bool = { true }
    ) async -> Bool {
        let probe = probe
        while !Task.isCancelled, keepWaiting() {
            if await Task.detached(operation: { probe.hasFullDiskAccess() }).value {
                grantAll()
                return true
            }
            do { try await Task.sleep(for: interval) } catch { return false }
        }
        return false
    }

    private func grantAll() {
        fullDiskAccess = true
        for folder in ProtectedFolder.allCases { folders[folder] = .allowed }
    }

    private var askedFolders: Set<ProtectedFolder> {
        Set((defaults.stringArray(forKey: Self.askedKey) ?? []).compactMap(ProtectedFolder.init(rawValue:)))
    }

    /// Off the main thread: while macOS's prompt is up, the read waits for the answer.
    private func read(_ folder: ProtectedFolder) async -> Bool {
        let probe = probe
        return await Task.detached(operation: { probe.canRead(folder) }).value
    }
}

/// The Mac's own folders.
public struct LiveFileAccessProbe: FileAccessProbe {
    public init() {}

    /// The real home folder, from the password database: a sandboxed debug launch sets
    /// CFFIXED_USER_HOME, which moves `FileManager`'s home but not what macOS protects.
    static var home: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(filePath: String(cString: dir), directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public func canRead(_ folder: ProtectedFolder) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.url(home: Self.home).path)) != nil
    }

    /// ~/Library/Safari is listed only with Full Disk Access: without it the read fails with EPERM
    /// and, unlike Desktop or another app's container (which on macOS 15 and later asks "would like
    /// to access data from other apps"), it never raises a prompt. Checked on macOS 27.0.1: a
    /// process without Full Disk Access gets "Operation not permitted". Safari ships with every
    /// Mac, but the folder appears only once it has run, so ~/Library/Mail (protected the same
    /// way) stands in when it isn't there. The user TCC database can't be used: without the
    /// access it reads as missing, the same as a database that isn't there.
    public func hasFullDiskAccess() -> Bool {
        let library = Self.home.appending(path: "Library", directoryHint: .isDirectory)
        return ["Safari", "Mail"].contains { name in
            (try? FileManager.default.contentsOfDirectory(atPath: library.appending(path: name).path)) != nil
        }
    }
}
