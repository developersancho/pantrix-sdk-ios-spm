//
//  FeedbackRuntime.swift
//  Pantrix
//
//  The single object behind the facade (§4c): it holds the configuration, checks the release gate, captures
//  the screen, presents the feedback form, and drives the mail/share submission. `@available(iOS 15.0, *)` and
//  `@MainActor` — the facade reaches it only from inside `if #available(iOS 15.0, *)`, so below iOS 15 nothing
//  here is touched.
//
//  Phase 1: capture → form → e-mail/share is live. Phase 2 adds the PencilKit annotation editor (wired via
//  the form's `onEditScreenshot`); Phase 3 adds the CoreMotion shake trigger.
//

import UIKit
import SwiftUI
import PantrixFeedbackKit

@available(iOS 15.0, *)
@MainActor
final class FeedbackRuntime {
    static let shared = FeedbackRuntime()

    private var config = FeedbackConfiguration()
    private let gate = FeedbackReleaseGate()
    private let motionShake = FeedbackMotionShake()
    private weak var presented: UIViewController?
    private var formModel: FeedbackFormModel?
    private var mailComposer: MailComposer?   // retained while the composer/share sheet is up

    private init() {}

    /// Whether feedback will actually open in this build — the gate result. The facade forwards this.
    var isAvailable: Bool {
        gate.isAvailable(debugOnly: config.debugOnly)
    }

    func enable(_ config: FeedbackConfiguration) {
        self.config = config
        guard isAvailable else { return }   // no shake in a gated-off build
        if config.enablesShakeGesture {
            motionShake.start(threshold: config.shakeThreshold) { [weak self] in self?.presentFromShake() }
        }
    }

    /// A device shake fired. Present from the frontmost scene's top view controller — but SKIP if a modal is
    /// already up (e.g. the inspector, opened by the same shake): don't stack feedback on top of it (§4d).
    private func presentFromShake() {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.keyWindow?.rootViewController, root.presentedViewController == nil else { return }
        show(from: root)
    }

    func configure(recipientEmail: String, subjectPrefix: String) {
        config.recipientEmail = recipientEmail
        config.subjectPrefix = subjectPrefix
    }

    // MARK: - Presentation

    func show(from presenter: UIViewController) {
        guard isAvailable, let screenshot = ScreenshotCapture.captureWindow(of: presenter) else { return }
        presentForm(screenshot: screenshot, from: presenter)
    }

    func showWithScreenshot(_ screenshot: UIImage, from presenter: UIViewController) {
        guard isAvailable else { return }
        presentForm(screenshot: screenshot, from: presenter)
    }

    private func presentForm(screenshot: UIImage, from presenter: UIViewController) {
        guard presented == nil else { return }   // don't stack a second form on a repeat trigger
        let model = FeedbackFormModel(screenshot: screenshot)
        formModel = model
        let form = FeedbackFormView(
            model: model,
            onSend: { [weak self] message in
                self?.finishForm { self?.submit(message: message, screenshot: model.screenshot, from: presenter) }
            },
            onCancel: { [weak self] in self?.finishForm(then: nil) },
            onEditScreenshot: { [weak self] in self?.presentAnnotation() }
        )
        let host = PantrixFeedbackHostController(rootView: form)
        host.modalPresentationStyle = .fullScreen
        topPresenter(from: presenter).present(host, animated: true)
        presented = host
    }

    /// Present the PencilKit editor on top of the form; on Done, update the shared `formModel.screenshot` so
    /// the form re-renders with the annotated image (Android `EditingScreenshot → onScreenshotEdited` parity).
    private func presentAnnotation() {
        guard let model = formModel, let host = presented else { return }
        let editor = PantrixFeedbackAnnotationController(
            screenshot: model.screenshot,
            onDone: { [weak host] merged in
                model.screenshot = merged
                host?.dismiss(animated: true)
            },
            onCancel: { [weak host] in host?.dismiss(animated: true) }
        )
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .fullScreen
        host.present(nav, animated: true)
    }

    /// Dismiss the form, then run `next` (submit) once it's off-screen so the mail/share sheet presents from a
    /// clean top-most controller.
    private func finishForm(then next: (() -> Void)?) {
        presented?.dismiss(animated: true, completion: next)
        presented = nil
    }

    private func submit(message: String, screenshot: UIImage, from presenter: UIViewController) {
        let subject = EmailComposition.subject(prefix: config.subjectPrefix, timestamp: Self.timestamp())
        let body = EmailComposition.body(
            message: message,
            deviceInfo: DeviceAppInfo.device(),
            appInfo: DeviceAppInfo.app()
        )
        let composer = MailComposer()
        mailComposer = composer
        composer.submit(
            from: topPresenter(from: presenter),
            recipient: config.recipientEmail,
            subject: subject,
            body: body,
            screenshot: screenshot
        ) { [weak self] in self?.mailComposer = nil }
    }

    func dismiss() {
        presented?.dismiss(animated: true)
        presented = nil
    }

    private func topPresenter(from presenter: UIViewController) -> UIViewController {
        var top = presenter
        while let next = top.presentedViewController { top = next }
        return top
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }
}

/// Hosts the feedback SwiftUI views. The ONLY reason it's a named subclass rather than a bare
/// `UIHostingController` is its class name: PantrixCore's automatic screen tracking skips any controller whose
/// class name starts with `PantrixFeedback`, so the feedback UI never records itself as an app screen in the
/// host's telemetry (§4i — the observer-effect the inspector had to fix too).
@available(iOS 15.0, *)
final class PantrixFeedbackHostController<Content: View>: UIHostingController<Content> {}
