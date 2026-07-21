//
//  AppExitAttrs.swift
//  Pantrix
//
//  The `app_exit` event's `event_attrs` — PantrixCore's `AppExitData`. Emitted with `eventName ==
//  "app_exit"` but `eventType == .performance`. Describes how the PREVIOUS run ended; `pid` is stringified
//  on the wire, `trace` is always absent on iOS. Consumed by `LaunchScopedEvent` to gate a stale row out.
//

import Foundation

public struct AppExitAttrs: Decodable, Equatable, Sendable {
    public let reasonId: Int
    public let reason: String
    public let importance: String
    public let trace: String?
    public let processName: String
    public let exitTimeMs: Int64
    public let pid: String
}
