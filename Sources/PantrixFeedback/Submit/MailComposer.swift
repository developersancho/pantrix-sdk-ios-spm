//
//  MailComposer.swift
//  Pantrix
//
//  Submits a feedback report (Android `FeedbackSender.sendViaEmail` parity). Prefers the system mail composer
//  (`MFMailComposeViewController`): recipient + subject + body + the annotated screenshot as a PNG attachment.
//  Falls back to the share sheet (`UIActivityViewController`) when there's no configured recipient OR the
//  device can't send mail (`canSendMail()` is false — no Mail account, or the Simulator). Nothing leaves the
//  device except through the destination the USER picks; Pantrix never sees it (§4g/§4i).
//
//  Retained by `FeedbackRuntime` while presenting (the mail delegate callback needs a live delegate).
//

import UIKit
import MessageUI

@available(iOS 15.0, *)
@MainActor
final class MailComposer: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
    private var onFinish: (() -> Void)?

    /// Presents the mail composer if possible, else the share sheet. `onFinish` fires when the user is done
    /// (sent/cancelled/shared) so the caller can drop its reference to this composer.
    func submit(
        from presenter: UIViewController,
        recipient: String,
        subject: String,
        body: String,
        screenshot: UIImage,
        onFinish: @escaping () -> Void
    ) {
        self.onFinish = onFinish

        if !recipient.isEmpty, MFMailComposeViewController.canSendMail() {
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = self
            mail.setToRecipients([recipient])
            mail.setSubject(subject)
            mail.setMessageBody(body, isHTML: false)
            if let png = screenshot.pngData() {
                mail.addAttachmentData(png, mimeType: "image/png", fileName: "feedback.png")
            }
            presenter.present(mail, animated: true)
        } else {
            presentShareSheet(from: presenter, subject: subject, body: body, screenshot: screenshot)
        }
    }

    /// Share sheet fallback: hand the body text + the screenshot image to `UIActivityViewController`. No
    /// temp file — the system copies the in-memory items — so there is nothing of ours to clean up afterwards
    /// (unlike Android's FileProvider path).
    private func presentShareSheet(from presenter: UIViewController, subject: String, body: String, screenshot: UIImage) {
        // The subject-aware activities (Mail) read the subject from a `UIActivityItemSource`; the plain
        // `String`/`UIImage` items carry the body + screenshot. (No fragile `setValue(_:forKey:"subject")`.)
        let items: [Any] = [FeedbackShareItem(subject: subject, body: body), screenshot]
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.finish()
        }
        // iPad: anchor the popover so it doesn't crash on a nil sourceView.
        sheet.popoverPresentationController?.sourceView = presenter.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0
        )
        sheet.popoverPresentationController?.permittedArrowDirections = []
        presenter.present(sheet, animated: true)
    }

    func mailComposeController(_ controller: MFMailComposeViewController,
                              didFinishWith result: MFMailComposeResult,
                              error: Error?) {
        controller.dismiss(animated: true) { [weak self] in self?.finish() }
    }

    private func finish() {
        let cb = onFinish
        onFinish = nil
        cb?()
    }
}

/// Carries the feedback body text into the share sheet AND exposes a subject the way subject-aware activities
/// (Mail) actually read it — via `UIActivityItemSource`, not a KVC hack.
@available(iOS 15.0, *)
private final class FeedbackShareItem: NSObject, UIActivityItemSource {
    private let subject: String
    private let body: String

    init(subject: String, body: String) {
        self.subject = subject
        self.body = body
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { body }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { body }

    func activityViewController(_ controller: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String { subject }
}
