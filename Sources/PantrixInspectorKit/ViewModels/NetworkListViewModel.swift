//
//  NetworkListViewModel.swift
//  Pantrix
//
//  Drives the Network screen: the `pntrx_network` table, newest first, keyset-paginated, live-refreshed off
//  the same store watermark (a captured request writes a `network` event too, so the watermark moves). An
//  `ObservableObject` in the Kit — the SwiftUI list just renders `state`.
//

import Foundation
import Combine

/// A display-ready network row. The view does no formatting (§4h).
public struct NetworkRowDisplay: Equatable, Identifiable, Sendable {
    public let id: String            // event_id
    public let method: String
    public let url: String
    public let statusCode: Int
    public let statusText: String
    public let clock: String
    public let durationText: String
    public let isError: Bool
    /// The raw date, for the keyset cursor + detail.
    public let date: String
}

@MainActor
public final class NetworkListViewModel: ObservableObject {
    @Published public private(set) var state: InspectorViewState<[NetworkRowDisplay]> = .loading
    @Published public private(set) var canLoadMore = false
    @Published public var searchText = "" { didSet { rebuild() } }

    private let store: InspectorStore
    private let config: CaptureConfig
    private let pageSize: Int
    private var loaded: [NetworkRecord] = []
    private var subscription: UUID?
    private var hasLoadedOnce = false

    public init(store: InspectorStore, config: CaptureConfig = .unknown, pageSize: Int = 100) {
        self.store = store
        self.config = config
        self.pageSize = pageSize
    }

    /// Subscribe + load. The store's polling lifecycle is the Runtime's (shared across view-models).
    public func start() {
        subscription = store.subscribe { [weak self] in self?.reload() }
        reload()
    }

    public func stop() {
        if let subscription { store.unsubscribe(subscription) }
        subscription = nil
    }

    public func reload() {
        if !hasLoadedOnce { state = .loading }
        do {
            loaded = try store.repo.network(pageSize: pageSize)
            canLoadMore = loaded.count == pageSize
            hasLoadedOnce = true
            rebuild()
        } catch {
            state = .error(InspectorViewState<[NetworkRowDisplay]>.describe(error))
        }
    }

    public func loadMore() {
        guard canLoadMore, let last = loaded.last else { return }
        do {
            let next = try store.repo.network(cursor: EventCursor(date: last.eventDate, id: last.eventId), pageSize: pageSize)
            loaded.append(contentsOf: next)
            canLoadMore = next.count == pageSize
            rebuild()
        } catch {
            state = .error(InspectorViewState<[NetworkRowDisplay]>.describe(error))
        }
    }

    /// The detail view model for a listed row, with the same capture config.
    public func detailViewModel(for rowId: String) -> NetworkDetailViewModel? {
        guard let record = loaded.first(where: { $0.eventId == rowId }) else { return nil }
        return NetworkDetailViewModel(record: record, config: config)
    }

    private func rebuild() {
        let visible = searchText.isEmpty ? loaded : loaded.filter { matches($0, searchText) }
        let rows = visible.map(display)
        state = rows.isEmpty ? .empty : .content(rows)
    }

    private func matches(_ record: NetworkRecord, _ text: String) -> Bool {
        let needle = text.lowercased()
        return record.url.lowercased().contains(needle)
            || record.method.lowercased().contains(needle)
            || String(record.statusCode).contains(needle)
    }

    private func display(_ record: NetworkRecord) -> NetworkRowDisplay {
        let status = Int(record.statusCode)
        return NetworkRowDisplay(
            id: record.eventId,
            method: record.method.isEmpty ? "GET" : record.method.uppercased(),
            url: record.url,
            statusCode: status,
            statusText: HttpStatusText.text(for: status),
            clock: InspectorFormatters.clock(fromISO: record.eventDate),
            durationText: InspectorFormatters.duration(millis: record.duration),
            isError: status >= 400 || !record.failureReason.isEmpty,
            date: record.eventDate
        )
    }
}
