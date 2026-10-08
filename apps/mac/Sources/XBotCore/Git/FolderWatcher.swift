import CoreServices
import Foundation

/// Calls back on the main queue when anything under a folder changes. FSEvents' own latency
/// (300 ms) gathers a burst of changes into one call.
public final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let box: Box

    /// Immutable, and only ever called on the main queue the stream delivers to.
    private final class Box: @unchecked Sendable {
        let action: @MainActor () -> Void
        init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    }

    public init(_ folder: URL, latency: TimeInterval = 0.3, onChange: @escaping @MainActor () -> Void) {
        box = Box(onChange)
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
                MainActor.assumeIsolated { box.action() }
            },
            &context, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
