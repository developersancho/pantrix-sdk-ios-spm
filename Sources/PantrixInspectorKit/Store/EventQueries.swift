//
//  EventQueries.swift
//  Pantrix
//
//  Builds the `pntrx_events` page query: keyset pagination + WHERE pushdown, all values BOUND. The only
//  thing built into the SQL string is the count of `?` placeholders for the `event_type IN (...)` list —
//  which is why an empty type filter drops the clause instead of emitting an invalid `IN ()`.
//
//  Row-value keyset `(event_date, event_id) < (?, ?)` needs SQLite ≥ 3.15; iOS 13's baseline is far newer.
//  The `ORDER BY event_date DESC, event_id DESC` matches the cursor comparison so the tie-break on equal
//  timestamps is stable.
//

import Foundation

enum EventQueries {
    /// The 23 columns of `pntrx_events`, in a fixed order. Read by name downstream, so the order here only
    /// has to be internally consistent, but it mirrors the table for readability.
    static let columns: [String] = {
        typealias E = InspectorSchema.Event
        return [
            E.eventId, E.eventName, E.eventDate, E.eventAttrs, E.eventType, E.sdkVersion, E.platform,
            E.installId, E.sessionId, E.buildId, E.deviceId, E.cdId, E.screenId, E.userId,
            E.sessionAttrs, E.deviceAttrs, E.buildAttrs, E.networkAttrs, E.screenAttrs, E.userAttrs,
            E.powerStateAttrs, E.threadName, E.isReported,
        ]
    }()

    /// SQL + ordered binds for one page. `pageSize` and every filter value are bound; the `IN` placeholder
    /// count is the only thing composed into the string.
    static func page(filter: EventFilter, cursor: EventCursor?, pageSize: Int) -> (sql: String, binds: [SQLiteBind]) {
        typealias E = InspectorSchema.Event
        var clauses: [String] = []
        var binds: [SQLiteBind] = []

        if let cursor {
            clauses.append("(\(E.eventDate), \(E.eventId)) < (?, ?)")
            binds.append(.text(cursor.date))
            binds.append(.text(cursor.id))
        }
        if !filter.types.isEmpty {
            let placeholders = Array(repeating: "?", count: filter.types.count).joined(separator: ", ")
            clauses.append("\(E.eventType) IN (\(placeholders))")
            binds.append(contentsOf: filter.types.map { .text($0.wireValue) })
        }
        if let sessionId = filter.sessionId {
            clauses.append("\(E.sessionId) = ?")
            binds.append(.text(sessionId))
        }
        if let screenId = filter.screenId {
            clauses.append("\(E.screenId) = ?")
            binds.append(.text(screenId))
        }
        if filter.reportedOnly {
            clauses.append("\(E.isReported) = 1")
        }
        if let fromDate = filter.fromDate {
            clauses.append("\(E.eventDate) >= ?")
            binds.append(.text(fromDate))
        }
        if let toDate = filter.toDate {
            clauses.append("\(E.eventDate) <= ?")
            binds.append(.text(toDate))
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        binds.append(.int(Int64(pageSize)))

        let sql = """
        SELECT \(columns.joined(separator: ", "))
        FROM \(E.table)
        \(whereClause)
        ORDER BY \(E.eventDate) DESC, \(E.eventId) DESC
        LIMIT ?
        """
        return (sql, binds)
    }

    /// Maps a row of the [columns] SELECT to a `RawEventRow` by name.
    static func map(_ row: SQLiteRow) -> RawEventRow {
        typealias E = InspectorSchema.Event
        return RawEventRow(
            eventId: row.requiredString(E.eventId),
            eventName: row.requiredString(E.eventName),
            eventDate: row.requiredString(E.eventDate),
            eventAttrs: row.string(E.eventAttrs),
            eventType: row.requiredString(E.eventType),
            sdkVersion: row.requiredString(E.sdkVersion),
            platform: row.requiredString(E.platform),
            installId: row.requiredString(E.installId),
            sessionId: row.requiredString(E.sessionId),
            buildId: row.requiredString(E.buildId),
            deviceId: row.requiredString(E.deviceId),
            cdId: row.string(E.cdId),
            screenId: row.string(E.screenId),
            userId: row.string(E.userId),
            sessionAttrs: row.requiredString(E.sessionAttrs),
            deviceAttrs: row.requiredString(E.deviceAttrs),
            buildAttrs: row.requiredString(E.buildAttrs),
            networkAttrs: row.requiredString(E.networkAttrs),
            screenAttrs: row.string(E.screenAttrs),
            userAttrs: row.string(E.userAttrs),
            powerStateAttrs: row.string(E.powerStateAttrs),
            threadName: row.string(E.threadName),
            isReported: row.bool(E.isReported)
        )
    }
}
