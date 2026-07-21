//
//  ShakeSwizzler.swift
//  Pantrix
//
//  Opens the inspector on a device shake by swizzling `-[UIWindow motionEnded:withEvent:]`. The subtlety
//  (§4d): `UIWindow` inherits `motionEnded` from `UIResponder`, so a naive `method_exchangeImplementations`
//  would hijack the shared `UIResponder` IMP — every responder in the process. Instead we `class_addMethod`
//  a UIWindow-SPECIFIC implementation (which calls the captured original), leaving `UIResponder` untouched.
//  Setup runs at most ONCE (a `lazy`-style guard). iOS 15-gated (§4c).
//
//  Why swizzle at all, rather than owning the window: a shake reaches the first responder first and only
//  travels up the responder chain if unhandled, so a host that handles shake itself is never overridden.
//

import UIKit

@available(iOS 15.0, *)
enum ShakeSwizzler {
    // Touched only on the main thread (UIKit motion events + install() from the main-actor facade).
    nonisolated(unsafe) private static var handler: ((UIWindow) -> Void)?
    nonisolated(unsafe) private static var installed = false

    /// Installs the shake hook (idempotent). `onShake` is handed the `UIWindow` that received the shake, so
    /// the caller can present from THAT window's scene — the shake path never needs a separately-tracked
    /// active scene (which the bubble-only observer wouldn't provide in a shake-only configuration).
    static func install(_ onShake: @escaping (UIWindow) -> Void) {
        handler = onShake
        guard !installed else { return }
        installed = true
        swizzle()
    }

    private static func swizzle() {
        let selector = #selector(UIResponder.motionEnded(_:with:))
        guard let inherited = class_getInstanceMethod(UIWindow.self, selector) else { return }
        let originalIMP = method_getImplementation(inherited)
        let types = method_getTypeEncoding(inherited)

        let block: @convention(block) (UIWindow, UIEvent.EventSubtype, UIEvent?) -> Void = { window, motion, event in
            if motion == .motionShake { handler?(window) }
            typealias OriginalFn = @convention(c) (UIWindow, Selector, UIEvent.EventSubtype, UIEvent?) -> Void
            unsafeBitCast(originalIMP, to: OriginalFn.self)(window, selector, motion, event)
        }
        let newIMP = imp_implementationWithBlock(block)

        // Add a UIWindow-OWN method (leaves UIResponder's inherited IMP alone). If UIWindow already had its
        // own override (it doesn't today), fall back to replacing that one.
        if !class_addMethod(UIWindow.self, selector, newIMP, types) {
            if let own = class_getInstanceMethod(UIWindow.self, selector) {
                method_setImplementation(own, newIMP)
            }
        }
    }
}
