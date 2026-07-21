//
//  InspectorEvent.swift
//  Pantrix
//
//  A `RawEventRow` plus typed access to what the UI asks for: the event `kind`, and on-demand decoders for
//  the seven context blobs and the per-event payload. Decoders THROW — a malformed blob surfaces, it is
//  never swallowed into an empty value. A nullable column that is absent decodes to `nil` (not an error);
//  a present-but-corrupt blob throws.
//

import Foundation

public struct InspectorEvent: Equatable, Sendable {
    public let row: RawEventRow

    public init(row: RawEventRow) { self.row = row }

    // MARK: - Row-level accessors

    public var id: String { row.eventId }
    public var name: String { row.eventName }
    public var date: String { row.eventDate }
    public var kind: EventKind { EventKind(wireValue: row.eventType) }
    public var sessionId: String { row.sessionId }
    public var screenId: String? { row.screenId }
    public var threadName: String? { row.threadName }
    public var isReported: Bool { row.isReported }
    /// The raw `event_attrs` JSON, for the "Raw" tab and generic display.
    public var rawEventAttrs: String? { row.eventAttrs }

    // MARK: - Context blobs (own columns)

    public func sessionAttrs() throws -> SessionAttrs { try Self.decode(row.sessionAttrs) }
    public func deviceAttrs() throws -> DeviceAttrs { try Self.decode(row.deviceAttrs) }
    public func buildAttrs() throws -> BuildAttrs { try Self.decode(row.buildAttrs) }
    public func networkContext() throws -> NetworkContextAttrs { try Self.decode(row.networkAttrs) }
    public func screenAttrs() throws -> ScreenAttrs? { try Self.decodeOptional(row.screenAttrs) }
    public func userAttrs() throws -> UserAttrs? { try Self.decodeOptional(row.userAttrs) }
    public func powerStateAttrs() throws -> PowerStateAttrs? { try Self.decodeOptional(row.powerStateAttrs) }

    // MARK: - Per-event payload (event_attrs), by kind/name

    /// Decode `event_attrs` as `T`, or `nil` when the column is absent. Throws on a present-but-corrupt blob.
    public func eventAttrs<T: Decodable>(_ type: T.Type) throws -> T? {
        try Self.decodeOptional(row.eventAttrs)
    }

    public func http() throws -> HttpAttrs? { try eventAttrs(HttpAttrs.self) }
    public func crash() throws -> CrashRecord? { try eventAttrs(CrashRecord.self) }
    public func memory() throws -> PerfAttrs? { try eventAttrs(PerfAttrs.self) }
    public func cpu() throws -> CpuAttrs? { try eventAttrs(CpuAttrs.self) }
    public func appExit() throws -> AppExitAttrs? { try eventAttrs(AppExitAttrs.self) }

    // MARK: - Decoding

    static func decode<T: Decodable>(_ json: String) throws -> T {
        // `Data(_:)` over a String's UTF-8 view can't fail (a Swift String is always valid UTF-8). A fresh
        // decoder each call — the default config already matches the SDK's encoder (no key strategy, so
        // keys are the literal property names), and it sidesteps sharing a non-Sendable `JSONDecoder`
        // across threads. The inspector decodes at UI cadence, not in a hot loop.
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static func decodeOptional<T: Decodable>(_ json: String?) throws -> T? {
        guard let json, !json.isEmpty else { return nil }
        return try decode(json)
    }
}
