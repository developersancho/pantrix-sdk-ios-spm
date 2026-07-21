//
//  InspectorRows.swift
//  Pantrix
//
//  Row shapes for the tables the inspector reads besides `pntrx_events`: sessions (section source),
//  screens (id→name), the denormalized network table, the crashes table, and the pipeline tables. These
//  hold column values verbatim; JSON columns (crash exceptions/threads, network headers) expose decoded
//  accessors that THROW on a corrupt blob rather than returning a default.
//

import Foundation

/// A `pntrx_sessions` row — the source of the events list's session sections.
public struct SessionRow: Equatable, Sendable {
    public let sessionId: String
    public let pid: Int64
    public let buildId: String
    public let startDate: String
    public let endDate: String?
    public let duration: Int64?
    public let crashed: Bool
}

/// A `pntrx_screens` row — resolves `screen_id` to a human name.
public struct ScreenRow: Equatable, Sendable {
    public let screenId: String
    public let screenName: String
    public let className: String
    public let category: String
}

/// A `pntrx_network` row — the denormalized HTTP record (22 columns). `requestHeaders`/`responseHeaders`
/// are stored as JSON strings here (unlike the `network` event's `event_attrs`, which stores maps).
public struct NetworkRecord: Equatable, Sendable {
    public let eventId: String
    public let eventName: String
    public let eventDate: String
    public let sessionId: String
    public let client: String
    public let url: String
    public let method: String
    public let statusCode: Int64
    public let path: String
    public let startTime: Int64
    public let endTime: Int64
    public let duration: Int64
    public let failureReason: String
    public let failureDescription: String
    public let requestHeaders: String
    public let responseHeaders: String
    public let requestBody: String
    public let responseBody: String
    public let proxies: String
    public let domainName: String
    public let dnsAddress: String
    public let networkProtocol: String

    /// `requestHeaders` decoded, or `nil` when the column is empty/`"{}"`. Throws on a corrupt blob.
    public func requestHeaderMap() throws -> [String: String]? { try Self.headerMap(requestHeaders) }
    public func responseHeaderMap() throws -> [String: String]? { try Self.headerMap(responseHeaders) }

    static func headerMap(_ json: String) throws -> [String: String]? {
        guard !json.isEmpty, json != "{}" else { return nil }
        return try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
    }
}

/// A `pntrx_crashes` row. `exceptions`/`threads` are JSON-array columns; decode them on demand.
public struct CrashRow: Equatable, Sendable {
    public let eventId: String
    public let eventName: String
    public let eventDate: String
    public let sessionId: String
    public let crashId: String
    public let className: String
    public let message: String
    public let exceptionsJSON: String
    public let threadsJSON: String
    public let handled: Bool
    public let foreground: Bool
    public let threadName: String

    public func exceptions() throws -> [ExceptionUnit] { try Self.decodeArray(exceptionsJSON) }
    public func threads() throws -> [ExceptionThread] { try Self.decodeArray(threadsJSON) }

    static func decodeArray<T: Decodable>(_ json: String) throws -> [T] {
        guard !json.isEmpty else { return [] }
        return try JSONDecoder().decode([T].self, from: Data(json.utf8))
    }
}

/// A `pntrx_batches` row — an upload batch awaiting or in flight.
public struct BatchRow: Equatable, Sendable {
    public let batchId: String
    public let createdAt: Int64
}

/// A `pntrx_events_batch` row — the event↔batch membership.
public struct EventBatchRow: Equatable, Sendable {
    public let eventId: String
    public let batchId: String
    public let createdAt: Int64
}

/// A `pntrx_app_exit` row — the pending app-exit pairing for a session/pid.
public struct AppExitRow: Equatable, Sendable {
    public let sessionId: String
    public let pid: Int64
    public let createdAt: Int64
    public let buildId: String
}
