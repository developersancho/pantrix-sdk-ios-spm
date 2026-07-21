//
//  PipelineViewModel.swift
//  Pantrix
//
//  Debugs the upload pipeline — the only way on-device to answer "why hasn't this event uploaded yet".
//  Reads `pntrx_batches` (with an event count joined from `pntrx_events_batch`) and `pntrx_app_exit`, and
//  classifies the last `app_exit` event via `LaunchScopedEvent` so a stale row from an earlier launch isn't
//  read as this run's. No Android equivalent.
//

import Foundation
import Combine

public struct BatchDisplay: Equatable, Identifiable, Sendable {
    public let batchId: String
    public let createdAt: Int64
    public let eventCount: Int
    public var id: String { batchId }
}

/// The `app_exit` readout in view-facing form, so the view never names the Kit's `LaunchScopedEvent`.
public struct LaunchDisplay: Equatable, Sendable {
    public let present: Bool
    public let stale: Bool
    public let rows: [DetailRow]

    static let none = LaunchDisplay(present: false, stale: false, rows: [])

    init(_ readout: LaunchScopedEvent.Readout) {
        switch readout {
        case .none:
            self = .none
        case .thisLaunch(let attrs):
            self.init(present: true, stale: false, attrs: attrs)
        case .stale(let attrs):
            self.init(present: true, stale: true, attrs: attrs)
        }
    }

    private init(present: Bool, stale: Bool, rows: [DetailRow]) {
        self.present = present; self.stale = stale; self.rows = rows
    }

    private init(present: Bool, stale: Bool, attrs: AppExitAttrs) {
        self.present = present
        self.stale = stale
        self.rows = [
            DetailRow(key: "reason", value: "\(attrs.reason) (\(attrs.reasonId))"),
            DetailRow(key: "importance", value: attrs.importance),
            DetailRow(key: "process", value: attrs.processName),
            DetailRow(key: "pid", value: attrs.pid),
        ]
    }
}

public struct PipelineSnapshot: Equatable, Sendable {
    public let batches: [BatchDisplay]
    public let appExits: [AppExitRow]
    public let launch: LaunchDisplay
}

@MainActor
public final class PipelineViewModel: ObservableObject {
    @Published public private(set) var state: InspectorViewState<PipelineSnapshot> = .loading

    private let store: InspectorStore
    private let processStartEpochMillis: Int64?
    private var subscription: UUID?
    private var hasLoadedOnce = false

    /// - Parameter processStartEpochMillis: this process's start time, so an `app_exit` row can be gated to
    ///   THIS launch. The Runtime supplies it (impure); tests inject it.
    public init(store: InspectorStore, processStartEpochMillis: Int64? = nil) {
        self.store = store
        self.processStartEpochMillis = processStartEpochMillis
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
            let batches = try store.repo.batches()
            let membership = try store.repo.eventBatches()
            let appExits = try store.repo.appExits()
            let appExitEvent = try store.repo.latestEvent(named: "app_exit")
            hasLoadedOnce = true

            var countByBatch: [String: Int] = [:]
            for row in membership { countByBatch[row.batchId, default: 0] += 1 }
            let batchDisplays = batches.map {
                BatchDisplay(batchId: $0.batchId, createdAt: $0.createdAt, eventCount: countByBatch[$0.batchId] ?? 0)
            }

            let readout = LaunchScopedEvent.classify(
                attrs: try appExitEvent?.appExit(),
                eventEpochMillis: appExitEvent.flatMap { InspectorFormatters.epochMillis(fromISO: $0.date) },
                processStartEpochMillis: processStartEpochMillis)
            let launch = LaunchDisplay(readout)

            let snapshot = PipelineSnapshot(batches: batchDisplays, appExits: appExits, launch: launch)
            let empty = batchDisplays.isEmpty && appExits.isEmpty && !launch.present
            state = empty ? .empty : .content(snapshot)
        } catch {
            state = .error(InspectorViewState<PipelineSnapshot>.describe(error))
        }
    }
}
