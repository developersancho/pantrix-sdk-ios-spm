//
//  InspectorRepository.swift
//  Pantrix
//
//  The single surface the view models (Phase 2+) see. It owns an `InspectorDatabase` and turns each table
//  into typed rows; the `*Queries` builders and raw SQLite plumbing never leak past here (the layer the
//  §4h rule protects). Every method THROWS on a read error — a locked device or a renamed column surfaces,
//  it is never a silently empty list.
//

import Foundation

public final class InspectorRepository: Sendable {
    private let db: InspectorDatabase

    /// Reads the store at `databaseURL`. `busyTimeoutMs` defaults to 250ms — long enough to ride out a
    /// same-process writer's WAL checkpoint, short enough not to stall the UI.
    public init(databaseURL: URL, busyTimeoutMs: Int32 = 250) {
        self.db = InspectorDatabase(url: databaseURL, busyTimeoutMs: busyTimeoutMs)
    }

    /// The repository against the SDK's default store location, or `nil` if it can't be resolved.
    public static func atDefaultLocation() -> InspectorRepository? {
        guard let url = InspectorPaths.databaseURL() else { return nil }
        return InspectorRepository(databaseURL: url)
    }

    // MARK: - Events

    /// One page of events, newest first, keyset-paginated. Pass the last event's `(date, id)` as `cursor`
    /// for the next page.
    public func events(filter: EventFilter = .none, cursor: EventCursor? = nil, pageSize: Int = 100) throws -> [InspectorEvent] {
        let (sql, binds) = EventQueries.page(filter: filter, cursor: cursor, pageSize: pageSize)
        return try db.rows(sql, binds: binds, map: EventQueries.map).map(InspectorEvent.init)
    }

    /// The newest event with a given name (e.g. `app_exit`, `anr`) — immune to any page window, for events
    /// emitted at most once per launch.
    public func latestEvent(named name: String) throws -> InspectorEvent? {
        typealias E = InspectorSchema.Event
        let sql = """
        SELECT \(EventQueries.columns.joined(separator: ", "))
        FROM \(E.table)
        WHERE \(E.eventName) = ?
        ORDER BY \(E.eventDate) DESC, \(E.eventId) DESC
        LIMIT 1
        """
        return try db.rows(sql, binds: [.text(name)], map: EventQueries.map).map(InspectorEvent.init).first
    }

    // MARK: - Sections + names

    public func sessions() throws -> [SessionRow] {
        try db.rows(SessionQueries.all, map: SessionQueries.map)
    }

    public func screens() throws -> [ScreenRow] {
        try db.rows(ScreenQueries.all, map: ScreenQueries.map)
    }

    /// Screens indexed by `screen_id`, for resolving an event's `screen_id` to a name.
    public func screensById() throws -> [String: ScreenRow] {
        Dictionary(try screens().map { ($0.screenId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Network

    public func network(cursor: EventCursor? = nil, pageSize: Int = 100) throws -> [NetworkRecord] {
        let (sql, binds) = NetworkQueries.page(cursor: cursor, pageSize: pageSize)
        return try db.rows(sql, binds: binds, map: NetworkQueries.map)
    }

    // MARK: - Crashes

    public func crashes(cursor: EventCursor? = nil, pageSize: Int = 100) throws -> [CrashRow] {
        let (sql, binds) = CrashQueries.page(cursor: cursor, pageSize: pageSize)
        return try db.rows(sql, binds: binds, map: CrashQueries.map)
    }

    // MARK: - Watermark (change detection)

    /// The three-component change watermark: row count, newest date, and the sum of `is_reported`. The
    /// third catches an in-place `is_reported` flip that leaves count and max-date unchanged (see
    /// [InspectorStore]). Throws on a read error, like every other query.
    public func watermark() throws -> Watermark {
        typealias E = InspectorSchema.Event
        let sql = """
        SELECT COUNT(*) AS cnt, MAX(\(E.eventDate)) AS maxDate, COALESCE(SUM(\(E.isReported)), 0) AS reportedSum
        FROM \(E.table)
        """
        let rows = try db.rows(sql) { row in
            Watermark(
                count: row.int64("cnt") ?? 0,
                maxDate: row.string("maxDate"),
                reportedSum: row.int64("reportedSum") ?? 0
            )
        }
        // A COUNT/SUM aggregate always returns exactly one row.
        return rows.first ?? Watermark(count: 0, maxDate: nil, reportedSum: 0)
    }

    // MARK: - Pipeline

    public func batches() throws -> [BatchRow] {
        try db.rows(PipelineQueries.batches, map: PipelineQueries.mapBatch)
    }

    public func eventBatches() throws -> [EventBatchRow] {
        try db.rows(PipelineQueries.eventsBatch, map: PipelineQueries.mapEventBatch)
    }

    public func appExits() throws -> [AppExitRow] {
        try db.rows(PipelineQueries.appExits, map: PipelineQueries.mapAppExit)
    }
}
