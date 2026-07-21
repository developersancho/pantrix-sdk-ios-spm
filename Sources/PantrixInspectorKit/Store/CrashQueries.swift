//
//  CrashQueries.swift
//  Pantrix
//
//  Reads `pntrx_crashes` (12 columns), newest first, keyset-paginated. The `exceptions`/`threads` columns
//  are JSON arrays kept as strings here — `CrashRow` decodes them on demand.
//

import Foundation

enum CrashQueries {
    static let columns: [String] = {
        typealias C = InspectorSchema.Crash
        return [
            C.eventId, C.eventName, C.eventDate, C.sessionId, C.crashId, C.className, C.message,
            C.exceptions, C.threads, C.handled, C.foreground, C.threadName,
        ]
    }()

    static func page(cursor: EventCursor?, pageSize: Int) -> (sql: String, binds: [SQLiteBind]) {
        typealias C = InspectorSchema.Crash
        var whereClause = ""
        var binds: [SQLiteBind] = []
        if let cursor {
            whereClause = "WHERE (\(C.eventDate), \(C.eventId)) < (?, ?)"
            binds.append(.text(cursor.date))
            binds.append(.text(cursor.id))
        }
        binds.append(.int(Int64(pageSize)))
        let sql = """
        SELECT \(columns.joined(separator: ", "))
        FROM \(C.table)
        \(whereClause)
        ORDER BY \(C.eventDate) DESC, \(C.eventId) DESC
        LIMIT ?
        """
        return (sql, binds)
    }

    static func map(_ row: SQLiteRow) -> CrashRow {
        typealias C = InspectorSchema.Crash
        return CrashRow(
            eventId: row.requiredString(C.eventId),
            eventName: row.requiredString(C.eventName),
            eventDate: row.requiredString(C.eventDate),
            sessionId: row.requiredString(C.sessionId),
            crashId: row.requiredString(C.crashId),
            className: row.requiredString(C.className),
            message: row.requiredString(C.message),
            exceptionsJSON: row.requiredString(C.exceptions),
            threadsJSON: row.requiredString(C.threads),
            handled: row.bool(C.handled),
            foreground: row.bool(C.foreground),
            threadName: row.requiredString(C.threadName)
        )
    }
}
