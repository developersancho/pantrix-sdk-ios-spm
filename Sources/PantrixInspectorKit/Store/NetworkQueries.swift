//
//  NetworkQueries.swift
//  Pantrix
//
//  Reads the denormalized `pntrx_network` table (22 columns), newest first, keyset-paginated on
//  `(event_date, event_id)` — the same stable ordering the events list uses.
//

import Foundation

enum NetworkQueries {
    static let columns: [String] = {
        typealias N = InspectorSchema.Network
        return [
            N.eventId, N.eventName, N.eventDate, N.sessionId, N.client, N.url, N.method, N.statusCode,
            N.path, N.startTime, N.endTime, N.duration, N.failureReason, N.failureDescription,
            N.requestHeaders, N.responseHeaders, N.requestBody, N.responseBody, N.proxies, N.domainName,
            N.dnsAddress, N.networkProtocol,
        ]
    }()

    static func page(cursor: EventCursor?, pageSize: Int) -> (sql: String, binds: [SQLiteBind]) {
        typealias N = InspectorSchema.Network
        var whereClause = ""
        var binds: [SQLiteBind] = []
        if let cursor {
            whereClause = "WHERE (\(N.eventDate), \(N.eventId)) < (?, ?)"
            binds.append(.text(cursor.date))
            binds.append(.text(cursor.id))
        }
        binds.append(.int(Int64(pageSize)))
        let sql = """
        SELECT \(columns.joined(separator: ", "))
        FROM \(N.table)
        \(whereClause)
        ORDER BY \(N.eventDate) DESC, \(N.eventId) DESC
        LIMIT ?
        """
        return (sql, binds)
    }

    static func map(_ row: SQLiteRow) -> NetworkRecord {
        typealias N = InspectorSchema.Network
        return NetworkRecord(
            eventId: row.requiredString(N.eventId),
            eventName: row.requiredString(N.eventName),
            eventDate: row.requiredString(N.eventDate),
            sessionId: row.requiredString(N.sessionId),
            client: row.requiredString(N.client),
            url: row.requiredString(N.url),
            method: row.requiredString(N.method),
            statusCode: row.int64(N.statusCode) ?? 0,
            path: row.requiredString(N.path),
            startTime: row.int64(N.startTime) ?? 0,
            endTime: row.int64(N.endTime) ?? 0,
            duration: row.int64(N.duration) ?? 0,
            failureReason: row.requiredString(N.failureReason),
            failureDescription: row.requiredString(N.failureDescription),
            requestHeaders: row.requiredString(N.requestHeaders),
            responseHeaders: row.requiredString(N.responseHeaders),
            requestBody: row.requiredString(N.requestBody),
            responseBody: row.requiredString(N.responseBody),
            proxies: row.requiredString(N.proxies),
            domainName: row.requiredString(N.domainName),
            dnsAddress: row.requiredString(N.dnsAddress),
            networkProtocol: row.requiredString(N.networkProtocol)
        )
    }
}
