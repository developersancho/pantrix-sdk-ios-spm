//
//  SessionQueries.swift
//  Pantrix
//
//  Reads `pntrx_sessions`, newest first — the source of the events list's section headers. Enumerated from
//  the sessions table directly (not derived from the events window), so a session's header never vanishes
//  just because its events scrolled off a page.
//

import Foundation

enum SessionQueries {
    static let all: String = {
        typealias S = InspectorSchema.Sessions
        return """
        SELECT \(S.sessionId), \(S.pid), \(S.buildId), \(S.startDate), \(S.endDate), \(S.duration), \(S.crashed)
        FROM \(S.table)
        ORDER BY \(S.startDate) DESC
        """
    }()

    static func map(_ row: SQLiteRow) -> SessionRow {
        typealias S = InspectorSchema.Sessions
        return SessionRow(
            sessionId: row.requiredString(S.sessionId),
            pid: row.int64(S.pid) ?? 0,
            buildId: row.requiredString(S.buildId),
            startDate: row.requiredString(S.startDate),
            endDate: row.string(S.endDate),
            duration: row.int64(S.duration),
            crashed: row.bool(S.crashed)
        )
    }
}
