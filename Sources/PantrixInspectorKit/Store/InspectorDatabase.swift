//
//  InspectorDatabase.swift
//  Pantrix
//
//  The inspector's read layer over the SDK's on-device store (`Library/Application Support/pntrx.db`).
//  Same-process, second read-only SQLite connection — WAL allows concurrent readers. No SDK internals are
//  used, only the documented schema ([InspectorSchema]). Phase 1 grows this into the full repository
//  (the Android inspector's data source, ported); this is the Phase 0 seed it builds on.
//
//  Two properties are load-bearing from the start: it opens with a busy timeout (so a writer's checkpoint
//  yields `SQLITE_BUSY` retries instead of an instant failure), and it reports failures through a typed
//  error, never by returning an empty collection. That distinction matters — a locked device or a missing
//  file must not read as "the SDK collected nothing".
//

import Foundation
import SQLite3

/// `SQLITE_TRANSIENT` is the C macro `((sqlite3_destructor_type)-1)`; macros that cast don't import into
/// Swift, so it is spelled out. It tells SQLite to COPY the bound bytes — without it the `String` a
/// `bind_text` bridges lives only for that call, and the following `sqlite3_step` would read freed memory.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

internal struct StoredEvent: Equatable {
    let eventId: String
    let name: String
    let type: String
    let date: String
    let screenId: String?
    let sessionId: String?
    let isReported: Bool
    /// Raw `event_attrs` JSON (custom-event payload), if any.
    let attrs: String?
}

internal struct SessionMeta: Equatable {
    let startDate: String?
    let duration: Int64?
    let crashed: Bool
}

/// Why a read failed. Kept distinct from an empty result so callers (and the eventual UI) can tell "no
/// rows" from "couldn't read" — returning `[]` on failure would conflate the two.
internal enum InspectorDatabaseError: Error, Equatable {
    /// The store file is not on disk — the SDK hasn't run yet, or ran under a different container.
    case databaseNotFound(path: String)
    /// `sqlite3_open_v2` failed (corrupt file, permissions, unreadable).
    case openFailed(code: Int32, message: String)
    /// `sqlite3_prepare_v2` failed — a renamed table/column (schema drift) lands here.
    case queryFailed(sql: String, code: Int32, message: String)
}

internal final class InspectorDatabase: Sendable {
    private let url: URL
    private let busyTimeoutMs: Int32

    /// - Parameter busyTimeoutMs: how long a query waits out a concurrent writer before giving up with
    ///   `SQLITE_BUSY`. 2s is generous for a same-process reader against WAL.
    init(url: URL, busyTimeoutMs: Int32 = 2000) {
        self.url = url
        self.busyTimeoutMs = busyTimeoutMs
    }

    /// The inspector against the SDK's default store location, or `nil` if Application Support can't be
    /// resolved. The file need not exist yet — that surfaces as `.databaseNotFound` on first query.
    static func atDefaultLocation() -> InspectorDatabase? {
        guard let url = InspectorPaths.databaseURL() else { return nil }
        return InspectorDatabase(url: url)
    }

    // MARK: - Queries

    /// The newest events, capped. (Phase 1 replaces the `LIMIT` with keyset pagination and the full
    /// 23-column row.)
    func recentEvents(limit: Int = 300) throws -> [StoredEvent] {
        try withConnection { db in
            typealias E = InspectorSchema.Event
            let sql = """
            SELECT \(E.eventId), \(E.eventName), \(E.eventType), \(E.eventDate), \
            \(E.screenId), \(E.sessionId), \(E.isReported), \(E.eventAttrs)
            FROM \(E.table)
            ORDER BY \(E.eventDate) DESC
            LIMIT \(limit)
            """
            return try query(db, sql, map: Self.mapEvent)
        }
    }

    /// The newest row for one event name. Immune to the `recentEvents` cap — the events this matters for
    /// (`app_exit`, `anr`) are emitted at most once per launch and scroll off a busy window first.
    func latestEvent(named name: String) throws -> StoredEvent? {
        try withConnection { db in
            typealias E = InspectorSchema.Event
            let sql = """
            SELECT \(E.eventId), \(E.eventName), \(E.eventType), \(E.eventDate), \
            \(E.screenId), \(E.sessionId), \(E.isReported), \(E.eventAttrs)
            FROM \(E.table)
            WHERE \(E.eventName) = ?
            ORDER BY \(E.eventDate) DESC
            LIMIT 1
            """
            let rows = try query(db, sql, bind: { stmt in
                sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
            }, map: Self.mapEvent)
            return rows.first
        }
    }

    /// Session metadata keyed by `session_id`, for the inspector's session section headers.
    func sessions() throws -> [String: SessionMeta] {
        try withConnection { db in
            typealias S = InspectorSchema.Sessions
            let sql = "SELECT \(S.sessionId), \(S.startDate), \(S.duration), \(S.crashed) FROM \(S.table)"
            let rows: [(String, SessionMeta)] = try query(db, sql) { stmt in
                let id = Self.text(stmt, 0) ?? ""
                return (id, SessionMeta(
                    startDate: Self.text(stmt, 1),
                    duration: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 2),
                    crashed: sqlite3_column_int64(stmt, 3) != 0
                ))
            }
            // session_id is the primary key, so keys are unique; keep the first defensively anyway.
            return Dictionary(rows.filter { !$0.0.isEmpty }, uniquingKeysWith: { first, _ in first })
        }
    }

    func eventCount() throws -> Int {
        try withConnection { db in
            let sql = "SELECT COUNT(*) FROM \(InspectorSchema.Event.table)"
            let rows: [Int] = try query(db, sql) { Int(sqlite3_column_int64($0, 0)) }
            return rows.first ?? 0
        }
    }

    // MARK: - Connection + statement plumbing

    /// Opens the store read-only (with the busy timeout) and runs `body` against the connection, closing it
    /// after. Internal so the query extensions (SQLiteReading.swift) can build on the same open/close +
    /// typed-error path rather than reopening the file themselves.
    func withConnection<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw InspectorDatabaseError.databaseNotFound(path: url.path)
        }
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let handle { sqlite3_close(handle) }
            throw InspectorDatabaseError.openFailed(code: rc, message: message)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, busyTimeoutMs)
        return try body(db)
    }

    /// Prepares and steps `sql`, mapping each row. A prepare failure — the shape schema drift takes —
    /// throws `.queryFailed` rather than yielding an empty array.
    private func query<T>(
        _ db: OpaquePointer,
        _ sql: String,
        bind: (OpaquePointer?) -> Void = { _ in },
        map: (OpaquePointer?) -> T
    ) throws -> [T] {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw InspectorDatabaseError.queryFailed(sql: sql, code: rc, message: message)
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(map(stmt)) }
        return out
    }

    /// Maps a stepped row of the eight-column event SELECT. Every `StoredEvent` query selects those
    /// columns, in that order.
    private static func mapEvent(_ stmt: OpaquePointer?) -> StoredEvent {
        StoredEvent(
            eventId: text(stmt, 0) ?? "",
            name: text(stmt, 1) ?? "?",
            type: text(stmt, 2) ?? "?",
            date: text(stmt, 3) ?? "",
            screenId: text(stmt, 4),
            sessionId: text(stmt, 5),
            isReported: sqlite3_column_int64(stmt, 6) != 0,
            attrs: text(stmt, 7)
        )
    }

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: c)
    }
}
