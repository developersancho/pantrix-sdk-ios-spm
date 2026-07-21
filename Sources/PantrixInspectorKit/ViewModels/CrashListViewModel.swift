//
//  CrashListViewModel.swift
//  Pantrix
//
//  Drives the Crashes screen: `pntrx_crashes`, newest first, live, with a stats card and All/Fatal/Handled/
//  ANR filter chips. Each row previews its blame frame (the first in-app stack line) so the list is scannable
//  without opening every crash. Fatal crashes are tinted. Behaviour is in the Kit; the view renders `state`.
//

import Foundation
import Combine

/// A display-ready crash row.
public struct CrashRowDisplay: Equatable, Identifiable, Sendable {
    public let id: String            // event_id
    public let kind: CrashKind
    public let title: String         // exception type / class, or "ANR"
    public let message: String
    public let blamePreview: String?  // top in-app frame, rendered
    public let clock: String
    public let date: String
    public var isFatal: Bool { kind == .fatal }
}

@MainActor
public final class CrashListViewModel: ObservableObject {
    public struct Stats: Equatable, Sendable {
        public let total: Int
        public let byKind: [CrashKind: Int]
        public func count(_ kind: CrashKind) -> Int { byKind[kind] ?? 0 }
    }

    @Published public private(set) var state: InspectorViewState<[CrashRowDisplay]> = .loading
    @Published public private(set) var stats = Stats(total: 0, byKind: [:])
    @Published public private(set) var canLoadMore = false
    @Published public private(set) var filter: CrashKind?   // nil = All

    private let store: InspectorStore
    private let pageSize: Int
    private var loaded: [CrashRow] = []
    private var subscription: UUID?
    private var hasLoadedOnce = false

    public init(store: InspectorStore, pageSize: Int = 100) {
        self.store = store
        self.pageSize = pageSize
    }

    public func start() {
        subscription = store.subscribe { [weak self] in self?.reload() }
        reload()
    }

    public func stop() {
        if let subscription { store.unsubscribe(subscription) }
        subscription = nil
    }

    public func setFilter(_ kind: CrashKind?) {
        filter = kind
        rebuild()
    }

    public func reload() {
        if !hasLoadedOnce { state = .loading }
        do {
            loaded = try store.repo.crashes(pageSize: pageSize)
            canLoadMore = loaded.count == pageSize
            hasLoadedOnce = true
            rebuild()
        } catch {
            state = .error(InspectorViewState<[CrashRowDisplay]>.describe(error))
        }
    }

    public func loadMore() {
        guard canLoadMore, let last = loaded.last else { return }
        do {
            let next = try store.repo.crashes(cursor: EventCursor(date: last.eventDate, id: last.eventId), pageSize: pageSize)
            loaded.append(contentsOf: next)
            canLoadMore = next.count == pageSize
            rebuild()
        } catch {
            state = .error(InspectorViewState<[CrashRowDisplay]>.describe(error))
        }
    }

    /// The detail view model for a listed row.
    public func detailViewModel(for rowId: String) -> CrashDetailViewModel? {
        guard let row = loaded.first(where: { $0.eventId == rowId }) else { return nil }
        return CrashDetailViewModel(row: row)
    }

    private func rebuild() {
        var byKind: [CrashKind: Int] = [:]
        for row in loaded { byKind[CrashKind.of(row), default: 0] += 1 }
        stats = Stats(total: loaded.count, byKind: byKind)

        let visible = filter.map { kind in loaded.filter { CrashKind.of($0) == kind } } ?? loaded
        let rows = visible.map(display)
        state = rows.isEmpty ? .empty : .content(rows)
    }

    private func display(_ row: CrashRow) -> CrashRowDisplay {
        let kind = CrashKind.of(row)
        let exceptions = (try? row.exceptions()) ?? []
        let firstException = exceptions.first
        let title = kind == .anr ? "ANR" : (firstException?.type ?? row.className).nonEmpty ?? "Crash"
        return CrashRowDisplay(
            id: row.eventId,
            kind: kind,
            title: title,
            message: (firstException?.message ?? row.message).nonEmpty ?? "",
            blamePreview: firstException.flatMap { FrameFormatter.blameLine($0.frames) },
            clock: InspectorFormatters.clock(fromISO: row.eventDate),
            date: row.eventDate
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
