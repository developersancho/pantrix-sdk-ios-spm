//
//  PipelineQueries.swift
//  Pantrix
//
//  Reads the upload-pipeline tables — `pntrx_batches`, `pntrx_events_batch`, `pntrx_app_exit`. There is no
//  Android equivalent; on iOS this is the only way to answer "why hasn't this event uploaded yet" from the
//  device. Small tables, read whole.
//

import Foundation

enum PipelineQueries {
    static let batches: String = {
        typealias B = InspectorSchema.Batches
        return "SELECT \(B.batchId), \(B.createdAt) FROM \(B.table) ORDER BY \(B.createdAt) ASC"
    }()

    static func mapBatch(_ row: SQLiteRow) -> BatchRow {
        typealias B = InspectorSchema.Batches
        return BatchRow(batchId: row.requiredString(B.batchId), createdAt: row.int64(B.createdAt) ?? 0)
    }

    static let eventsBatch: String = {
        typealias E = InspectorSchema.EventsBatch
        return "SELECT \(E.eventId), \(E.batchId), \(E.createdAt) FROM \(E.table) ORDER BY \(E.createdAt) ASC"
    }()

    static func mapEventBatch(_ row: SQLiteRow) -> EventBatchRow {
        typealias E = InspectorSchema.EventsBatch
        return EventBatchRow(
            eventId: row.requiredString(E.eventId),
            batchId: row.requiredString(E.batchId),
            createdAt: row.int64(E.createdAt) ?? 0
        )
    }

    static let appExits: String = {
        typealias A = InspectorSchema.AppExit
        return """
        SELECT \(A.sessionId), \(A.pid), \(A.createdAt), \(A.buildId)
        FROM \(A.table)
        ORDER BY \(A.createdAt) DESC
        """
    }()

    static func mapAppExit(_ row: SQLiteRow) -> AppExitRow {
        typealias A = InspectorSchema.AppExit
        return AppExitRow(
            sessionId: row.requiredString(A.sessionId),
            pid: row.int64(A.pid) ?? 0,
            createdAt: row.int64(A.createdAt) ?? 0,
            buildId: row.requiredString(A.buildId)
        )
    }
}
