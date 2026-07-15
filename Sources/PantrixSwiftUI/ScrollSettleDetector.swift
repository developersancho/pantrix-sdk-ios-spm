//
//  ScrollSettleDetector.swift
//  PantrixSwiftUI
//
//  Created by developersancho on 15.07.2026.
//

import Foundation

/// Turns a stream of scroll offsets into one "settled" event per gesture — the iOS-13 stand-in for
/// Android's `snapshotFlow { isScrollInProgress }.distinctUntilChanged().drop(1).filter { !it }`.
///
/// iOS 13 exposes no scroll state (no `isScrollInProgress`, no offset), so a real falling-edge detector
/// can't be ported. Instead each new offset re-arms a timer; when the timer survives `settleAfter`
/// with no further change, the scroll has settled and the resting offset is emitted. Two rules mirror
/// Android exactly:
///   • the FIRST offset is swallowed as a baseline (the `.drop(1)` — merely laying out the list must
///     not emit a `ui_scroll`);
///   • an offset equal to the last one is ignored (the `distinctUntilChanged`).
///
/// `schedule` is the injectable seam: the default arms a main-queue `DispatchWorkItem`, tests pass a
/// fake so the whole state machine runs deterministically with no real timer.
@MainActor
internal final class ScrollSettleDetector {

    /// Arms `work` to run after `delay`, returning a closure that cancels it if called first. `work`
    /// touches the detector's main-actor state, so the whole seam is main-actor-isolated — which is
    /// also what lets the production timer hop back onto the main queue safely. Everything here stays
    /// on the main actor, so nothing needs to be `Sendable`.
    typealias Schedule = @MainActor (_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> () -> Void

    private let schedule: Schedule
    private var hasBaseline = false
    private var latestOffset = 0
    private var cancelPending: (() -> Void)?

    init(schedule: @escaping Schedule = ScrollSettleDetector.mainQueueSchedule) {
        self.schedule = schedule
    }

    /// Feeds one offset (points) into the detector. Re-arms the settle timer unless this is the
    /// baseline or an unchanged value.
    func report(offset: Int, settleAfter: TimeInterval, emit: @escaping (Int) -> Void) {
        guard hasBaseline else {
            hasBaseline = true
            latestOffset = offset
            return
        }
        guard offset != latestOffset else { return }
        latestOffset = offset

        cancelPending?()
        cancelPending = schedule(settleAfter) { [weak self] in
            guard let self else { return }
            self.cancelPending = nil
            emit(self.latestOffset)
        }
    }

    /// The production seam: a cancellable main-queue delay. The work item runs on the main queue, so
    /// re-entering the main actor for `work` is sound.
    @MainActor
    static func mainQueueSchedule(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> () -> Void {
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}
