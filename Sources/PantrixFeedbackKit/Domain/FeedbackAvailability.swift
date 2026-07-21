//
//  FeedbackAvailability.swift
//  Pantrix
//
//  The pure decision behind the feedback release gate (§4a). The view target's `FeedbackReleaseGate` does the
//  impure probing (simulator? `get-task-allow` in the embedded profile?) and feeds the result here. Kept in
//  the Kit so the decision — the whole "does this ship to end users" boundary — is unit-tested and counted,
//  while the probing stays in the exempt view target.
//
//  Rule (Android `shouldSkipInit` parity, inverted to "is available"): feedback runs when the build is a
//  development context (simulator, or a build carrying `get-task-allow`), OR when the host turns OFF
//  `debugOnly`. `debugOnly = false` is the documented path for a TestFlight QA build, where `get-task-allow`
//  is absent — the analogue of the inspector's `allowsInReleaseBuilds`.
//

import Foundation

public enum FeedbackAvailability {
    /// - Parameters:
    ///   - isSimulator: running on the Simulator (always a dev context).
    ///   - hasGetTaskAllow: the build carries `get-task-allow` (dev-signed; absent on App Store / TestFlight).
    ///   - debugOnly: the host's opt-in — when `false`, feedback is available even in a non-debuggable build.
    public static func decide(isSimulator: Bool, hasGetTaskAllow: Bool, debugOnly: Bool) -> Bool {
        !debugOnly || isSimulator || hasGetTaskAllow
    }
}
