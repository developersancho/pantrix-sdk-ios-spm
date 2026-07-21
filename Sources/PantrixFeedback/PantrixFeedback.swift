//
//  PantrixFeedback.swift
//  Pantrix
//
//  Public entry point for the in-app user-feedback tool (screenshot → annotate → e-mail/share). This file is
//  the FACADE only — it carries no `@available`, so a host names it (and `FeedbackConfiguration`) on any
//  iOS 13+ deployment. The real UI and window plumbing live behind an `@available(iOS 15.0, *)`
//  `FeedbackRuntime`, which these methods reach through an `if #available` fence; below iOS 15 they are inert.
//
//  `@_exported import PantrixFeedbackKit` re-exports the Kit so a single `import PantrixFeedback` brings
//  `FeedbackConfiguration` into scope — the product ships only this target, and the Kit reaches consumers
//  through here (§4b/§4c of the port plan). Same mechanism the umbrella uses for PantrixCore.
//

@_exported import PantrixFeedbackKit
import UIKit

public enum PantrixFeedback {

    /// Whether feedback will actually open in this build — the release gate's verdict. A host uses it to show
    /// or hide its own "Send Feedback" affordance so a rejected build (App Store / non-debuggable) doesn't
    /// leave a dead control. `false` below iOS 15, otherwise the gate result.
    @MainActor
    public static var isAvailable: Bool {
        if #available(iOS 15.0, *) { return FeedbackRuntime.shared.isAvailable }
        return false
    }

    /// Wire feedback into the host: stores the configuration and, when enabled, installs the shake gesture.
    /// A no-op below iOS 15, and gated at runtime by the build's debuggability (`debugOnly`). Call it once,
    /// early — from a SwiftUI `App.init` or the UIKit app delegate.
    @MainActor
    public static func enable(_ config: FeedbackConfiguration = .init()) {
        if #available(iOS 15.0, *) { FeedbackRuntime.shared.enable(config) }
    }

    /// Convenience over `enable`: set just the e-mail recipient + subject prefix (Android `configure` parity).
    @MainActor
    public static func configure(recipientEmail: String, subjectPrefix: String = "[App Feedback]") {
        if #available(iOS 15.0, *) {
            FeedbackRuntime.shared.configure(recipientEmail: recipientEmail, subjectPrefix: subjectPrefix)
        }
    }

    /// Capture the current screen and open the feedback flow, presented from `presenter`. A no-op when
    /// unavailable (below iOS 15 or the gate rejected this build).
    @MainActor
    public static func show(from presenter: UIViewController) {
        if #available(iOS 15.0, *) { FeedbackRuntime.shared.show(from: presenter) }
    }

    /// Open the feedback flow with a screenshot you already hold, presented from `presenter`.
    @MainActor
    public static func showWithScreenshot(_ screenshot: UIImage, from presenter: UIViewController) {
        if #available(iOS 15.0, *) { FeedbackRuntime.shared.showWithScreenshot(screenshot, from: presenter) }
    }

    /// Dismiss the feedback flow if it is showing.
    @MainActor
    public static func dismiss() {
        if #available(iOS 15.0, *) { FeedbackRuntime.shared.dismiss() }
    }
}
