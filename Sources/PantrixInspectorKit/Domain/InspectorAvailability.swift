//
//  InspectorAvailability.swift
//  Pantrix
//
//  The pure decision behind the release gate (§4a). The view target's `ReleaseGate` does the impure probing
//  (simulator? `get-task-allow` in the embedded profile?) and feeds the result here. Kept in the Kit so the
//  decision — which is the whole security boundary — is unit-tested and counted, while the probing stays in
//  the exempt view target.
//
//  Rule: the inspector is available in a development context (simulator, or a build carrying the
//  `get-task-allow` entitlement), OR when the host explicitly opts in with `allowsInReleaseBuilds`. The
//  opt-in is the documented path for a TestFlight QA build, where `get-task-allow` is absent (§4a) — a
//  deliberate choice, not an accident.
//

import Foundation

public enum InspectorAvailability {
    /// - Parameters:
    ///   - isSimulator: running on the Simulator (always a dev context).
    ///   - hasGetTaskAllow: the build carries `get-task-allow` (dev-signed; absent on App Store / TestFlight).
    ///   - allowsInReleaseBuilds: the host's explicit opt-in.
    public static func decide(isSimulator: Bool, hasGetTaskAllow: Bool, allowsInReleaseBuilds: Bool) -> Bool {
        isSimulator || hasGetTaskAllow || allowsInReleaseBuilds
    }
}
