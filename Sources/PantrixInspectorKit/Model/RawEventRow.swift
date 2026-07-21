//
//  RawEventRow.swift
//  Pantrix
//
//  All 23 columns of a `pntrx_events` row, accessed by name. The `*_attrs` columns arrive as raw JSON
//  strings (decoded lazily by [InspectorEvent]); the four context blobs are `NOT NULL`, the rest are
//  nullable. This is a plain value type; the query layer (Phase 1b) builds it from a statement via a
//  name→index map so a column reorder in the SDK can't silently shift a field.
//

import Foundation

public struct RawEventRow: Equatable, Sendable {
    public let eventId: String
    public let eventName: String
    public let eventDate: String
    public let eventAttrs: String?
    public let eventType: String
    public let sdkVersion: String
    public let platform: String
    public let installId: String
    public let sessionId: String
    public let buildId: String
    public let deviceId: String
    public let cdId: String?
    public let screenId: String?
    public let userId: String?
    public let sessionAttrs: String
    public let deviceAttrs: String
    public let buildAttrs: String
    public let networkAttrs: String
    public let screenAttrs: String?
    public let userAttrs: String?
    public let powerStateAttrs: String?
    public let threadName: String?
    public let isReported: Bool

    public init(
        eventId: String, eventName: String, eventDate: String, eventAttrs: String?,
        eventType: String, sdkVersion: String, platform: String, installId: String,
        sessionId: String, buildId: String, deviceId: String, cdId: String?,
        screenId: String?, userId: String?, sessionAttrs: String, deviceAttrs: String,
        buildAttrs: String, networkAttrs: String, screenAttrs: String?, userAttrs: String?,
        powerStateAttrs: String?, threadName: String?, isReported: Bool
    ) {
        self.eventId = eventId
        self.eventName = eventName
        self.eventDate = eventDate
        self.eventAttrs = eventAttrs
        self.eventType = eventType
        self.sdkVersion = sdkVersion
        self.platform = platform
        self.installId = installId
        self.sessionId = sessionId
        self.buildId = buildId
        self.deviceId = deviceId
        self.cdId = cdId
        self.screenId = screenId
        self.userId = userId
        self.sessionAttrs = sessionAttrs
        self.deviceAttrs = deviceAttrs
        self.buildAttrs = buildAttrs
        self.networkAttrs = networkAttrs
        self.screenAttrs = screenAttrs
        self.userAttrs = userAttrs
        self.powerStateAttrs = powerStateAttrs
        self.threadName = threadName
        self.isReported = isReported
    }
}
