//
//  ScreenshotCapture.swift
//  Pantrix
//
//  Captures the current screen for the feedback flow — the iOS analogue of Android's `ScreenshotCapture`
//  (PixelCopy). `UIGraphicsImageRenderer` + `drawHierarchy(in:afterScreenUpdates:)` on the key window renders
//  the live view hierarchy to a `UIImage`. `afterScreenUpdates: false` grabs the screen AS IT IS NOW, before
//  the feedback modal animates in.
//
//  Known limit (documented, §4e): `drawHierarchy` renders the UIKit/SwiftUI view tree, so DRM/secure content
//  (a protected `AVPlayer` layer, a field marked secure) comes out black — the same trade every in-app
//  screenshotter makes. Impure (lives in the exempt view target).
//

import UIKit

@available(iOS 15.0, *)
enum ScreenshotCapture {
    /// Renders `view` (typically the key window) to an image at screen scale.
    static func capture(_ view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = view.window?.screen.scale ?? UIScreen.main.scale
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
    }

    /// Captures the window hosting `presenter`, or `nil` if it isn't in a window yet.
    static func captureWindow(of presenter: UIViewController) -> UIImage? {
        guard let window = presenter.view.window else { return nil }
        return capture(window)
    }
}
