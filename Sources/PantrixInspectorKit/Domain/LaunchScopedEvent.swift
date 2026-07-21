//
//  LaunchScopedEvent.swift
//  Pantrix
//
//  Gates an `app_exit` row by staleness. `app_exit` describes how the PREVIOUS run ended, is emitted at
//  most once per launch (and never on the simulator), and — with retention effectively off — old rows live
//  forever. So the newest row is NOT necessarily this launch's: crash on device → relaunch emits
//  `app_exit CRASH` → then a plain run from Xcode emits nothing → the newest row still says CRASH, two
//  launches stale. Comparing the row's event time against THIS process's start time separates the two.
//
//  The classifier is pure — it takes the already-parsed epochs, so it is fully testable; the host supplies
//  the process start time (Phase 2+).
//

import Foundation

public enum LaunchScopedEvent {

    public enum Readout: Equatable, Sendable {
        /// Emitted by THIS launch — safe to render as "how the previous run ended".
        case thisLaunch(AppExitAttrs)
        /// A real row from an earlier launch — render only with an explicit "not this launch" label.
        case stale(AppExitAttrs)
        /// No `app_exit` row at all.
        case none
    }

    /// Classifies an `app_exit` payload against this process's start time.
    /// - Parameters:
    ///   - attrs: the decoded `app_exit` payload, or `nil` for no row.
    ///   - eventEpochMillis: the row's `event_date` as epoch ms (parse with `InspectorFormatters`).
    ///   - processStartEpochMillis: this process's start time as epoch ms.
    ///
    /// A missing payload is `.none`. If either epoch is unknown the row can't be placed in time, so it is
    /// `.stale` — "this launch" is a claim that needs evidence, and a wrong attribution is the whole failure
    /// mode above; the empty/stale states cost nothing.
    public static func classify(
        attrs: AppExitAttrs?,
        eventEpochMillis: Int64?,
        processStartEpochMillis: Int64?
    ) -> Readout {
        guard let attrs else { return .none }
        guard let eventMs = eventEpochMillis, let startMs = processStartEpochMillis else {
            return .stale(attrs)
        }
        return eventMs >= startMs ? .thisLaunch(attrs) : .stale(attrs)
    }
}
