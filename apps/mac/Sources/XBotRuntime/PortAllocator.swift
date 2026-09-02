import Darwin
import Foundation

/// Finds a port that is actually free, by binding it.
///
/// Never assume. A Homebrew Postgres on 5432 is the common case on a developer's Mac, and the
/// failure it produces — the engine connecting to the wrong database and reporting
/// `role "openbot" does not exist` — reads as a bug in xBot rather than a collision.
public enum PortAllocator {
    /// Bind-test candidates and return the first that takes.
    ///
    /// A bind test rather than a connect test: connecting tells you whether something is *answering*
    /// now, which is a different question. A socket bound by a process that is not accepting yet
    /// would pass a connect probe and then refuse the real bind seconds later.
    public static func allocate(
        preferred: UInt16,
        range: ClosedRange<UInt16>
    ) throws -> UInt16 {
        if isFree(preferred) { return preferred }
        for candidate in range where isFree(candidate) {
            return candidate
        }
        throw RuntimeError.noFreePort(range: range)
    }

    public static func isFree(_ port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        // Without SO_REUSEADDR a port left in TIME_WAIT by our own previous run reads as taken,
        // and the app would walk to a new port on every restart — which is exactly the moving
        // port that breaks bookmarks and the admin webview.
        var reuse: Int32 = 1
        setsockopt(
            descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        // Loopback only, matching how the container publishes. Testing 0.0.0.0 would ask a
        // different and more permissive question than the one we act on.
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bound == 0
    }
}
