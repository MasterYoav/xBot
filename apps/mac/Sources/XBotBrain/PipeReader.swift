import Foundation

/**
 What a pipe carries, as chunks, read on a thread of the pipe's own.

 Not `FileHandle.bytes`: Foundation does those reads, blocking, on one serial queue shared by every
 handle in the process. A read waiting on one pipe (a CLI's stderr, quiet until it exits) holds up
 every other, so the CLI's stdout stopped being read, filled up, and its last line (a schema'd
 answer, ~47 KB) was lost or the CLI hung writing it. Two turns at once waited on each other too.
 Not a `readabilityHandler` either: it fires again and again once the pipe reaches end-of-file.
 */
public enum PipeReader {
    public static func chunks(_ handle: FileHandle) -> AsyncStream<Data> {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        let fd = handle.fileDescriptor
        let thread = Thread {
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                if count > 0 {
                    continuation.yield(Data(buffer[0..<count]))
                } else if count < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
            continuation.finish()
        }
        thread.name = "xBot pipe reader"
        thread.start()
        return stream
    }

    /// Everything until end-of-file.
    public static func readAll(_ handle: FileHandle) async -> Data {
        var data = Data()
        for await chunk in chunks(handle) { data.append(chunk) }
        return data
    }
}
