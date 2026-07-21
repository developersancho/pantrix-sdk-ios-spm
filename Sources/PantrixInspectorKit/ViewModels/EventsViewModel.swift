//
//  EventsViewModel.swift
//  Pantrix
//
//  Drives the Events screen: one keyset-paginated, filtered, searchable list grouped into session sections,
//  plus the header stats — refreshed live off the store's watermark. An `ObservableObject` in the Kit (not
//  the view target) so all of this is unit-tested; the SwiftUI view just renders `state` and `stats`.
//
//  iOS 13-available (Combine / `@Published` / `@MainActor` are all 13+), so it doesn't drag the Kit above
//  the package floor — only the SwiftUI views that observe it are iOS 15.
//

import Foundation
import Combine

/// A display-ready event row. The view does no formatting (§4h) — `clock` and everything else is prepared
/// here.
public struct EventRowDisplay: Equatable, Identifiable, Sendable {
    public let id: String            // event_id
    public let name: String
    public let kind: EventKind
    public let clock: String         // formatted local time
    public let date: String          // raw ISO, for the detail + the keyset cursor
    public let screenName: String?
    public let isReported: Bool
}

/// A session's rows, under a resolved (already-formatted) session header. The view renders these strings —
/// it does no formatting (§4h).
public struct EventSection: Equatable, Identifiable, Sendable {
    public let sessionId: String
    public let headerTitle: String       // formatted session start, or a short id fallback
    public let durationText: String?     // formatted session duration, if known
    public let crashed: Bool
    public let rows: [EventRowDisplay]
    public var id: String { sessionId }
}

/// The Events header numbers, as a view-facing type (so the view never names the Kit's `Aggregations`).
public struct InspectorEventStats: Equatable, Sendable {
    public struct Chip: Equatable, Sendable, Identifiable {
        public let kind: EventKind
        public let count: Int
        public var id: String { kind.wireValue }
    }
    public let total: Int
    public let reported: Int
    public let typeCount: Int
    public let chips: [Chip]

    static let empty = InspectorEventStats(total: 0, reported: 0, typeCount: 0, chips: [])
}

@MainActor
public final class EventsViewModel: ObservableObject {
    @Published public private(set) var state: InspectorViewState<[EventSection]> = .loading
    @Published public private(set) var stats = InspectorEventStats.empty
    @Published public private(set) var canLoadMore = false
    @Published public private(set) var searchText = ""

    private var filter: EventFilter = .none

    /// The currently-selected type filter, for the filter sheet (which speaks `EventKind`, not `EventFilter`).
    public var selectedTypes: [EventKind] { filter.types }
    /// The current reported-only toggle, for the filter sheet.
    public var reportedOnly: Bool { filter.reportedOnly }

    private let store: InspectorStore
    private let pageSize: Int
    private var loaded: [InspectorEvent] = []
    private var sessionsById: [String: SessionRow] = [:]
    private var screensById: [String: ScreenRow] = [:]
    private var subscription: UUID?
    private var hasLoadedOnce = false

    public init(store: InspectorStore, pageSize: Int = 100) {
        self.store = store
        self.pageSize = pageSize
    }

    /// The repository, for the detail screen (which reads the same store).
    public var repository: InspectorRepository { store.repo }

    /// The detail view model for a listed row, resolving its screen name — or `nil` if the row isn't in the
    /// currently loaded page. Keeps the event lookup in the Kit so the view just navigates.
    public func detailViewModel(for rowId: String) -> EventDetailViewModel? {
        guard let event = loaded.first(where: { $0.id == rowId }) else { return nil }
        let screenName = event.screenId.flatMap { screensById[$0]?.screenName }
        return EventDetailViewModel(event: event, screenName: screenName)
    }

    // MARK: - Lifecycle

    /// Subscribe to live changes and load the first page. The store's polling lifecycle is owned by the
    /// Runtime (many view-models share one store), so this only subscribes + loads — it does not start or
    /// stop the store's timer.
    public func start() {
        subscription = store.subscribe { [weak self] in self?.reload() }
        reload()
    }

    public func stop() {
        if let subscription { store.unsubscribe(subscription) }
        subscription = nil
    }

    // MARK: - Filter + search

    public func setFilter(_ newFilter: EventFilter) {
        filter = newFilter
        reload()   // filter is pushed into the query, so it re-fetches
    }

    /// Apply a filter expressed in view terms (`EventKind`s + reported-only) — the sheet never builds an
    /// `EventFilter` itself, keeping the query type in the Kit.
    public func applyFilter(types: [EventKind], reportedOnly: Bool) {
        setFilter(EventFilter(types: types, reportedOnly: reportedOnly))
    }

    public func setSearch(_ text: String) {
        searchText = text
        rebuild()  // search is client-side over the loaded page
    }

    // MARK: - Loading

    public func reload() {
        if !hasLoadedOnce { state = .loading }
        do {
            loaded = try store.repo.events(filter: filter, pageSize: pageSize)
            sessionsById = Dictionary(try store.repo.sessions().map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
            screensById = try store.repo.screensById()
            canLoadMore = loaded.count == pageSize
            hasLoadedOnce = true
            rebuild()
        } catch {
            state = .error(InspectorViewState<[EventSection]>.describe(error))
        }
    }

    public func loadMore() {
        guard canLoadMore, let last = loaded.last else { return }
        do {
            let next = try store.repo.events(filter: filter, cursor: EventCursor(date: last.date, id: last.id), pageSize: pageSize)
            loaded.append(contentsOf: next)
            canLoadMore = next.count == pageSize
            rebuild()
        } catch {
            state = .error(InspectorViewState<[EventSection]>.describe(error))
        }
    }

    // MARK: - Rebuild (search + sections + stats)

    private func rebuild() {
        let raw = Aggregations.eventStats(loaded)   // header counts reflect everything loaded, not the search
        stats = InspectorEventStats(
            total: raw.total,
            reported: raw.reported,
            typeCount: raw.byKind.keys.count,
            chips: raw.kindsByFrequency.map { InspectorEventStats.Chip(kind: $0.kind, count: $0.count) }
        )
        let visible = searchText.isEmpty ? loaded : loaded.filter { matches($0, searchText) }
        let sections = buildSections(visible)
        state = sections.isEmpty ? .empty : .content(sections)
    }

    private func matches(_ event: InspectorEvent, _ text: String) -> Bool {
        let needle = text.lowercased()
        if event.name.lowercased().contains(needle) { return true }
        if event.kind.wireValue.lowercased().contains(needle) { return true }
        if let screen = event.screenId.flatMap({ screensById[$0]?.screenName }), screen.lowercased().contains(needle) { return true }
        return false
    }

    private func buildSections(_ events: [InspectorEvent]) -> [EventSection] {
        // Preserve the (date DESC) event order within each session, and order sessions by first appearance
        // in that already-sorted stream — i.e. by their newest event, matching the list's top-to-bottom flow.
        var order: [String] = []
        var grouped: [String: [EventRowDisplay]] = [:]
        for event in events {
            let sid = event.sessionId
            if grouped[sid] == nil { order.append(sid) }
            grouped[sid, default: []].append(display(event))
        }
        return order.map { sid in
            let session = sessionsById[sid]
            return EventSection(
                sessionId: sid,
                headerTitle: session.map { InspectorFormatters.clock(fromISO: $0.startDate) } ?? "session \(sid.prefix(8))",
                durationText: session?.duration.map { InspectorFormatters.duration(millis: $0) },
                crashed: session?.crashed ?? false,
                rows: grouped[sid] ?? []
            )
        }
    }

    private func display(_ event: InspectorEvent) -> EventRowDisplay {
        EventRowDisplay(
            id: event.id,
            name: event.name,
            kind: event.kind,
            clock: InspectorFormatters.clock(fromISO: event.date),
            date: event.date,
            screenName: event.screenId.flatMap { screensById[$0]?.screenName },
            isReported: event.isReported
        )
    }
}
