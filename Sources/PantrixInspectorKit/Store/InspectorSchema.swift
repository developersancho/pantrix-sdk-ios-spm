//
//  InspectorSchema.swift
//  Pantrix
//
//  The `pntrx.db` schema the inspector reads, COPIED from PantrixCore's internal `DbConstants`. It has to
//  be copied, not imported: PantrixCore ships as a closed binary whose schema constants are `internal`,
//  and the Kit deliberately has no dependency on it (§4b of the port plan). The copy is not free-floating
//  — `InspectorSchemaParityTests` asserts every name here equals PantrixCore's (via `@testable import`),
//  and `InspectorSchemaDriftTests` checks them against a real `PRAGMA table_info`, so a rename in the SDK
//  turns into a red test, not a silently blank screen.
//
//  Every query the Kit runs references these constants (never a hardcoded string), so the parity test
//  guards the actual SQL, not just a lookup table.
//

import Foundation

internal enum InspectorSchema {
    static let databaseName = "pntrx.db"

    enum Event {
        static let table = "pntrx_events"
        static let eventId = "event_id"
        static let eventName = "event_name"
        static let eventDate = "event_date"
        static let eventAttrs = "event_attrs"
        static let eventType = "event_type"
        static let sdkVersion = "sdk_version"
        static let platform = "platform"
        static let installId = "install_id"
        static let sessionId = "session_id"
        static let buildId = "build_id"
        static let deviceId = "device_id"
        static let cdId = "cd_id"
        static let screenId = "screen_id"
        static let userId = "user_id"
        static let sessionAttrs = "session_attrs"
        static let deviceAttrs = "device_attrs"
        static let buildAttrs = "build_attrs"
        static let networkAttrs = "network_attrs"
        static let screenAttrs = "screen_attrs"
        static let userAttrs = "user_attrs"
        static let powerStateAttrs = "power_state_attrs"
        static let threadName = "thread_name"
        static let isReported = "is_reported"
    }

    enum Sessions {
        static let table = "pntrx_sessions"
        static let sessionId = "session_id"
        static let pid = "pid"
        static let buildId = "build_id"
        static let startDate = "start_date"
        static let endDate = "end_date"
        static let duration = "duration"
        static let crashed = "crashed"
    }

    enum Screens {
        static let table = "pntrx_screens"
        static let screenId = "screen_id"
        static let screenName = "screen_name"
        static let className = "class_name"
        static let category = "category"
    }

    enum Batches {
        static let table = "pntrx_batches"
        static let batchId = "batch_id"
        static let createdAt = "created_at"
    }

    enum EventsBatch {
        static let table = "pntrx_events_batch"
        static let eventId = "event_id"
        static let batchId = "batch_id"
        static let createdAt = "created_at"
    }

    enum AppExit {
        static let table = "pntrx_app_exit"
        static let sessionId = "session_id"
        static let pid = "pid"
        static let createdAt = "created_at"
        static let buildId = "build_id"
    }

    enum Crash {
        static let table = "pntrx_crashes"
        static let eventId = "event_id"
        static let eventName = "event_name"
        static let eventDate = "event_date"
        static let sessionId = "session_id"
        static let crashId = "crash_id"
        static let className = "class_name"
        static let message = "message"
        static let exceptions = "exceptions"
        static let threads = "threads"
        static let handled = "handled"
        static let foreground = "foreground"
        static let threadName = "thread_name"
    }

    enum Network {
        static let table = "pntrx_network"
        static let eventId = "event_id"
        static let eventName = "event_name"
        static let eventDate = "event_date"
        static let sessionId = "session_id"
        static let client = "client"
        static let url = "url"
        static let method = "method"
        static let statusCode = "status_code"
        static let path = "path"
        static let startTime = "start_time"
        static let endTime = "end_time"
        static let duration = "duration"
        static let failureReason = "failure_reason"
        static let failureDescription = "failure_description"
        static let requestHeaders = "request_headers"
        static let responseHeaders = "response_headers"
        static let requestBody = "request_body"
        static let responseBody = "response_body"
        static let proxies = "proxies"
        static let domainName = "domain_name"
        static let dnsAddress = "dns_address"
        static let networkProtocol = "protocol"
    }
}
