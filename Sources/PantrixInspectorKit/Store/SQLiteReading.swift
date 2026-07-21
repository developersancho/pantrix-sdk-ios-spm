//
//  SQLiteReading.swift
//  Pantrix
//
//  Name-indexed row reading + positional parameter binding for the inspector's queries. Columns are read
//  by NAME (a name→index map built once per statement), so a column reorder in the SDK's DDL can't silently
//  shift a field into the wrong Swift property. Values are always BOUND, never interpolated — the only
//  thing a query builds into its SQL string is the COUNT of `?` placeholders for an `IN` list.
//

import Foundation
import SQLite3

/// `SQLITE_TRANSIENT` — see InspectorDatabase.swift for why it's spelled out. SQLite copies the bound bytes.
let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One bound parameter. `.text(nil)` binds SQL NULL (same as `.null`).
enum SQLiteBind: Equatable {
    case text(String?)
    case int(Int64)
    case null

    func bind(_ stmt: OpaquePointer?, _ position: Int32) {
        switch self {
        case .text(let value?): sqlite3_bind_text(stmt, position, value, -1, sqliteTransient)
        case .text(nil), .null: sqlite3_bind_null(stmt, position)
        case .int(let value): sqlite3_bind_int64(stmt, position, value)
        }
    }
}

/// A stepped row, read by column name. Holds the statement and the shared (built-once) name→index map.
struct SQLiteRow {
    let stmt: OpaquePointer?
    let index: [String: Int32]

    func string(_ column: String) -> String? {
        guard let i = index[column], sqlite3_column_type(stmt, i) != SQLITE_NULL,
              let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }

    /// A column declared NOT NULL — falls back to "" only if the row is unexpectedly null, never crashes.
    func requiredString(_ column: String) -> String { string(column) ?? "" }

    func int64(_ column: String) -> Int64? {
        guard let i = index[column], sqlite3_column_type(stmt, i) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(stmt, i)
    }

    func bool(_ column: String) -> Bool { (int64(column) ?? 0) != 0 }
}

extension InspectorDatabase {
    /// Prepares `sql`, binds `binds` positionally, and maps every row by NAME. The index map is built once
    /// per statement, not per row. A prepare failure (the shape schema drift takes) throws `.queryFailed`.
    func rows<T>(_ sql: String, binds: [SQLiteBind] = [], map: (SQLiteRow) -> T) throws -> [T] {
        try withConnection { db in
            var stmt: OpaquePointer?
            let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            guard rc == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(db))
                throw InspectorDatabaseError.queryFailed(sql: sql, code: rc, message: message)
            }
            defer { sqlite3_finalize(stmt) }

            var index: [String: Int32] = [:]
            let columnCount = sqlite3_column_count(stmt)
            index.reserveCapacity(Int(columnCount))
            for i in 0..<columnCount {
                if let c = sqlite3_column_name(stmt, i) { index[String(cString: c)] = i }
            }
            for (offset, bind) in binds.enumerated() { bind.bind(stmt, Int32(offset + 1)) }

            var out: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(map(SQLiteRow(stmt: stmt, index: index)))
            }
            return out
        }
    }
}
