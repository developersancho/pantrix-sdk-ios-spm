//
//  TimelineViewModel.swift
//  Pantrix
//
//  A session-oriented timeline: sessions (newest first) from `pntrx_sessions`, each with its events as
//  type-tagged nodes. Sections come from the sessions table directly (not derived from an event window), so
//  a session never disappears just because its events scrolled off.
//

import Foundation
import Combine

public struct TimelineNode: Equatable, Identifiable, Sendable {
    public let id: String        // event_id
    public let kind: EventKind
    public let name: String
    public let clock: String
}

public struct TimelineSession: Equatable, Identifiable, Sendable {
    public let sessionId: String
    public let headerTitle: String
    public let durationText: String?
    public let crashed: Bool
    public let nodes: [TimelineNode]
    public var id: String { sessionId }
}

@MainActor
public final class TimelineViewModel: ObservableObject {
    @Published public private(set) var state: InspectorViewState<[TimelineSession]> = .loading

    private let store: InspectorStore
    private let pageSize: Int
    private var subscription: UUID?
    private var hasLoadedOnce = false

    public init(store: InspectorStore, pageSize: Int = 300) {
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

    public func reload() {
        if !hasLoadedOnce { state = .loading }
        do {
            let events = try store.repo.events(pageSize: pageSize)
            let sessions = try store.repo.sessions()
            hasLoadedOnce = true
            let timeline = Self.build(sessions: sessions, events: events)
            state = timeline.isEmpty ? .empty : .content(timeline)
        } catch {
            state = .error(InspectorViewState<[TimelineSession]>.describe(error))
        }
    }

    static func build(sessions: [SessionRow], events: [InspectorEvent]) -> [TimelineSession] {
        var nodesBySession: [String: [TimelineNode]] = [:]
        for event in events {
            nodesBySession[event.sessionId, default: []].append(TimelineNode(
                id: event.id, kind: event.kind, name: event.name,
                clock: InspectorFormatters.clock(fromISO: event.date)))
        }
        // Sessions in the table's order (newest start first); only those with nodes are shown.
        return sessions.compactMap { session in
            guard let nodes = nodesBySession[session.sessionId], !nodes.isEmpty else { return nil }
            return TimelineSession(
                sessionId: session.sessionId,
                headerTitle: InspectorFormatters.clock(fromISO: session.startDate),
                durationText: session.duration.map { InspectorFormatters.duration(millis: $0) },
                crashed: session.crashed,
                nodes: nodes)
        }
    }
}
