//
//  EventFilter.swift
//  Pantrix
//
//  The query parameters for an events page: which types, which session/screen, reported-only, a date
//  window. Empty/`nil` fields mean "no constraint" — an empty `types` is NOT "match nothing", it drops the
//  `IN` clause entirely (a literal `IN ()` is invalid SQL, and the intent is "all types").
//

import Foundation

public struct EventFilter: Equatable, Sendable {
    public var types: [EventKind]
    public var sessionId: String?
    public var screenId: String?
    public var reportedOnly: Bool
    /// ISO-8601 STRING bounds compared lexicographically against `event_date` — never INTEGER millis.
    public var fromDate: String?
    public var toDate: String?

    public init(
        types: [EventKind] = [],
        sessionId: String? = nil,
        screenId: String? = nil,
        reportedOnly: Bool = false,
        fromDate: String? = nil,
        toDate: String? = nil
    ) {
        self.types = types
        self.sessionId = sessionId
        self.screenId = screenId
        self.reportedOnly = reportedOnly
        self.fromDate = fromDate
        self.toDate = toDate
    }

    public static let none = EventFilter()
}

/// A keyset cursor — the `(event_date, event_id)` of the last row of the previous page. The next page asks
/// for rows strictly ordered before it. Keyset, never OFFSET, so a page can't skip or repeat rows when the
/// store grows underneath the scroll.
public struct EventCursor: Equatable, Sendable {
    public let date: String
    public let id: String
    public init(date: String, id: String) {
        self.date = date
        self.id = id
    }
}
