//
//  PantrixFeedbackNoop.swift
//  Pantrix
//
//  No-op twin of `PantrixFeedback` — the iOS analogue of Android's `pantrix-feedback-noop`. It replicates
//  the PUBLIC API of `PantrixFeedback` (the facade + `FeedbackConfiguration`) as inert stubs, so a host can
//  link THIS product in a Release / App Store build instead of the real `PantrixFeedback`. The real feedback
//  UI code — and its `PantrixFeedbackKit` logic — then never ship in that binary.
//
//  SPM has no per-configuration dependency like Gradle's `releaseImplementation`, so the swap is a
//  per-configuration LINK in the host's Xcode target plus a compile guard on the import:
//
//      #if PANTRIX_FEEDBACK              // your own flag, defined only on Debug / QaTest
//      import PantrixFeedback           // real
//      #else
//      import PantrixFeedbackNoop       // this — inert
//      #endif
//      ...
//      PantrixFeedback.show(from: self)   // identical call site against either module
//
//  Every symbol here mirrors `PantrixFeedback` exactly (names, signatures, defaults, `@MainActor`) so the
//  host's call sites compile unchanged whichever module is imported.
//

import UIKit

/// Inert twin of `FeedbackConfiguration` — same fields and defaults, no behaviour.
public struct FeedbackConfiguration: Sendable {
    public var debugOnly: Bool = true
    public var recipientEmail: String = ""
    public var subjectPrefix: String = "[App Feedback]"
    public var enablesShakeGesture: Bool = false
    public var shakeThreshold: Double = 2.5
    public init() {}
}

/// Inert twin of `PantrixFeedback`. Every entry point is a no-op; `isAvailable` is always `false`.
public enum PantrixFeedback {

    @MainActor
    public static var isAvailable: Bool { false }

    @MainActor
    public static func enable(_ config: FeedbackConfiguration = .init()) {}

    @MainActor
    public static func configure(recipientEmail: String, subjectPrefix: String = "[App Feedback]") {}

    @MainActor
    public static func show(from presenter: UIViewController) {}

    @MainActor
    public static func showWithScreenshot(_ screenshot: UIImage, from presenter: UIViewController) {}

    @MainActor
    public static func dismiss() {}
}
