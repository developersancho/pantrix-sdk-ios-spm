//
//  InspectorStore.swift
//  Pantrix
//
//  The live-refresh coordinator: one repository, one 2-second poll, N subscribers. Each tick reads a
//  THREE-component watermark and notifies subscribers only when it moved — so the screens refresh on real
//  change, not on a timer.
//
//  The third component is not optional. A successful batch upload UPDATES rows in place
//  (`is_reported` 0→1) and only deletes them in a LATER step, so a flip changes neither the row COUNT nor
//  `MAX(event_date)`. A count-and-max watermark would miss it, and a "reported only" view would freeze.
//  `SUM(is_reported)` is the component that moves on a flip (and also on insert/delete), so the three
//  together cover insert, delete, and flip.
//

import Foundation

/// The change-detection watermark for `pntrx_events`.
public struct Watermark: Equatable, Sendable {
    public let count: Int64
    public let maxDate: String?
    public let reportedSum: Int64
}

@MainActor
public final class InspectorStore {
    private let repository: InspectorRepository
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private var lastWatermark: Watermark?
    private var subscribers: [UUID: () -> Void] = [:]

    public init(repository: InspectorRepository, pollInterval: TimeInterval = 2.0) {
        self.repository = repository
        self.pollInterval = pollInterval
    }

    /// The repository the screens query. Subscribers read through this after being notified.
    public var repo: InspectorRepository { repository }

    /// The last watermark seen, or `nil` before the first successful poll.
    public var currentWatermark: Watermark? { lastWatermark }

    // MARK: - Subscription

    /// Register for change notifications. Returns a token to unsubscribe with.
    @discardableResult
    public func subscribe(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        return id
    }

    public func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    // MARK: - Polling

    /// Read the watermark once; if it changed (including the first read), notify every subscriber. Returns
    /// whether it changed. A read error leaves the last watermark in place and does NOT notify — a locked
    /// device shouldn't look like "nothing changed" forever, but it also shouldn't spuriously refresh.
    @discardableResult
    public func poll() -> Bool {
        guard let watermark = try? repository.watermark() else { return false }
        guard watermark != lastWatermark else { return false }
        lastWatermark = watermark
        for handler in subscribers.values { handler() }
        return true
    }

    /// Start polling: an immediate poll, then every `pollInterval` on the main run loop. Idempotent — a
    /// second `start()` without an intervening `stop()` invalidates the previous timer first, so re-opening
    /// the inspector never leaks a timer that would keep polling `pntrx.db` forever.
    public func start() {
        timer?.invalidate()
        poll()
        let interval = pollInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}
