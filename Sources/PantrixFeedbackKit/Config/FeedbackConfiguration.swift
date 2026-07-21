//
//  FeedbackConfiguration.swift
//  Pantrix
//
//  Knobs for the in-app feedback tool. Lives in `PantrixFeedbackKit` (not the view target) and carries NO
//  `@available`, on purpose: it appears in `PantrixFeedback.enable(_ config:)` / `configure(...)`, and an
//  annotated type in an un-annotated facade signature would drag the whole facade above the package's iOS 13
//  floor. So the type is iOS 13-available even though the UI that reads it is iOS 15+ (§4c of the port plan).
//  Mirrors Android `FeedbackConfig` field-for-field. All defaults are the safest value.
//

import Foundation

public struct FeedbackConfiguration: Sendable {
    /// Only activate in a DEBUGGABLE build (dev-signed / simulator). Default **true**, so a shipped App Store
    /// build never shows feedback even if `enable()` is left in. Set **false** to reach it in a TestFlight QA
    /// build, where `get-task-allow` is absent — the documented, deliberate opt-in (§4a), the analogue of the
    /// inspector's `allowsInReleaseBuilds`. Consumed by the release gate.
    public var debugOnly: Bool = true

    /// Where a submitted feedback e-mail is addressed. Empty → the tool skips the mail composer and shares via
    /// the system share sheet instead (Android's `recipientEmail.isBlank()` parity).
    public var recipientEmail: String = ""

    /// Prefix for the feedback e-mail subject (`"<prefix> <timestamp>"`). Android default `"[App Feedback]"`.
    public var subjectPrefix: String = "[App Feedback]"

    /// Open the feedback flow on a device shake. Off by default. Detected via CoreMotion (NOT a `motionEnded`
    /// swizzle) so it never clobbers `PantrixInspector`'s shake hook when both add-ons are used (§4d).
    public var enablesShakeGesture: Bool = false

    /// Acceleration magnitude (in g, above rest) that counts as a shake. Android default `2.5f`.
    public var shakeThreshold: Double = 2.5

    public init() {}
}
