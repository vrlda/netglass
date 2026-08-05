import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DatabaseError: Error, Equatable {
    case openFailed(String)
    case sqlite(String)
}

public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?

    public init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw DatabaseError.openFailed(message)
        }
    }

    public func exec(_ sql: String, _ bindings: [SQLBinding] = []) throws {
        try sql.withCString { start in
            var cursor: UnsafePointer<CChar>? = start
            while let current = cursor {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(handle, current, -1, &statement, &cursor) == SQLITE_OK else {
                    throw DatabaseError.sqlite(errorMessage())
                }
                guard let statement else { break }
                do {
                    try bind(bindings, to: statement)
                    let result = sqlite3_step(statement)
                    guard result == SQLITE_DONE || result == SQLITE_ROW else {
                        throw DatabaseError.sqlite(errorMessage())
                    }
                } catch {
                    sqlite3_finalize(statement)
                    throw error
                }
                sqlite3_finalize(statement)
            }
        }
    }

    public func prepare(_ sql: String) throws -> Statement {
        try Statement(handle: handle, sql: sql)
    }

    public func close() {
        if let handle { sqlite3_close(handle) }
        self.handle = nil
    }

    deinit { close() }

    private func bind(_ bindings: [SQLBinding], to statement: OpaquePointer?) throws {
        let paramCount = sqlite3_bind_parameter_count(statement)
        guard paramCount == bindings.count else {
            throw DatabaseError.sqlite("expected \(bindings.count) bindings, statement has \(paramCount)")
        }
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case .blob(let value):
                result = value.withUnsafeBytes { raw in
                    sqlite3_bind_blob(statement, index, raw.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
                }
            case .int(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw DatabaseError.sqlite(errorMessage()) }
        }
    }

    private func errorMessage() -> String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }
}

public final class Statement: @unchecked Sendable {
    private var statement: OpaquePointer?
    private let handle: OpaquePointer?

    fileprivate init(handle: OpaquePointer?, sql: String) throws {
        self.handle = handle
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw DatabaseError.sqlite(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown")
        }
    }

    public func bind(_ bindings: [SQLBinding]) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case .blob(let value):
                result = value.withUnsafeBytes { raw in
                    sqlite3_bind_blob(statement, index, raw.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
                }
            case .int(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw DatabaseError.sqlite(lastError()) }
        }
    }

    public func step() throws -> Bool {
        guard let statement else { return false }
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw DatabaseError.sqlite(lastError())
    }

    public func text(_ index: Int32) -> String {
        guard !isNull(index) else { return "" }
        return String(cString: sqlite3_column_text(statement, index))
    }

    public func blob(_ index: Int32) -> [UInt8] {
        guard let raw = sqlite3_column_blob(statement, index) else { return [] }
        let count = Int(sqlite3_column_bytes(statement, index))
        return [UInt8](UnsafeRawBufferPointer(start: raw, count: count))
    }

    public func int64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    public func double(_ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    public func isNull(_ index: Int32) -> Bool {
        sqlite3_column_type(statement, index) == SQLITE_NULL
    }

    public func close() {
        if let statement { sqlite3_finalize(statement) }
        self.statement = nil
    }

    deinit { close() }

    private func lastError() -> String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }
}
