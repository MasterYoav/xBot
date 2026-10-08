import Foundation
import SQLite3

/// The smallest SQLite wrapper that does the job: one connection, a statement prepared per call.
/// ponytail: no statement cache; add one if a profile ever shows prepare time.
public final class Database {
    public enum Value: Equatable {
        case text(String)
        case real(Double)
        case null
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    private var handle: OpaquePointer?

    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try open(url.path)
        try execute("PRAGMA journal_mode = WAL")
    }

    /// A private database that lives as long as this object.
    public init() throws {
        try open(":memory:")
    }

    deinit { sqlite3_close_v2(handle) }

    private func open(_ path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw Failure(description: message)
        }
        try execute("PRAGMA foreign_keys = ON")
    }

    public func execute(_ sql: String, _ values: [Value] = []) throws {
        _ = try rows(sql, values)
    }

    public func rows(_ sql: String, _ values: [Value] = []) throws -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure(description: message)
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, transient)
            case .real(let number): sqlite3_bind_double(statement, position, number)
            case .null: sqlite3_bind_null(statement, position)
            }
        }

        var result: [[Value]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                result.append((0..<sqlite3_column_count(statement)).map { column in
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_NULL: .null
                    case SQLITE_FLOAT, SQLITE_INTEGER: .real(sqlite3_column_double(statement, column))
                    default: .text(String(cString: sqlite3_column_text(statement, column)))
                    }
                })
            case SQLITE_DONE:
                return result
            default:
                throw Failure(description: message)
            }
        }
    }

    private var message: String { String(cString: sqlite3_errmsg(handle)) }
}

extension Database.Value {
    var string: String? { if case .text(let text) = self { text } else { nil } }
    var uuid: UUID? { string.flatMap(UUID.init(uuidString:)) }
    /// Dates are kept as Foundation's own reference-date seconds, so they come back bit-for-bit.
    var date: Date {
        if case .real(let seconds) = self { Date(timeIntervalSinceReferenceDate: seconds) } else { .distantPast }
    }

    static func date(_ date: Date) -> Self { .real(date.timeIntervalSinceReferenceDate) }

    var number: Double { if case .real(let n) = self { n } else { 0 } }

    var bool: Bool { if case .real(let n) = self { n != 0 } else { false } }
    static func bool(_ value: Bool) -> Self { .real(value ? 1 : 0) }
}

extension Optional where Wrapped == String {
    var sql: Database.Value { map(Database.Value.text) ?? .null }
}
