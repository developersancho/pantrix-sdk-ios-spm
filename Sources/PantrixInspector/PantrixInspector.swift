//
//  PantrixInspector.swift
//  Pantrix
//
//  Public entry point for the on-device debug inspector. This file is the FACADE only — it carries no
//  `@available`, so a host names it (and `InspectorConfiguration`) on any iOS 13+ deployment. The real UI
//  and window plumbing live behind an `@available(iOS 15.0, *)` `Runtime` (added in Phase 2), which these
//  methods reach through an `if #available` fence; below iOS 15 they are inert.
//
//  `@_exported import PantrixInspectorKit` re-exports the Kit so a single `import PantrixInspector` brings
//  `InspectorConfiguration` into scope — the product ships only this target, and the Kit reaches consumers
//  through here (§4b/§4c of the port plan). Same mechanism the umbrella uses for PantrixCore.
//
//  The bodies forward to the `@available(iOS 15.0, *)` `Runtime` behind an availability fence; below iOS 15
//  they are inert (`isAvailable == false`, `makeViewController() == nil`, the rest no-ops).
//

@_exported import PantrixInspectorKit
import UIKit

public enum PantrixInspector {

    /// Whether the inspector will actually open in this build. A host uses it to show or hide its own
    /// "Open Inspector" affordance, so a rejected build (App Store / non-debuggable) doesn't leave a dead
    /// menu item. `false` below iOS 15, otherwise the release gate's verdict.
    @MainActor
    public static var isAvailable: Bool {
        if #available(iOS 15.0, *) { return Runtime.shared.isAvailable }
        return false
    }

    /// Wire the inspector into the host. A no-op below iOS 15, and gated at runtime by the build's
    /// debuggability. Call it once, early — from a SwiftUI `App.init` or the UIKit app delegate; wrapping
    /// the call in the host's own `#if DEBUG` is the recommended way to keep it out of release.
    @MainActor
    public static func enable(_ config: InspectorConfiguration = .init()) {
        if #available(iOS 15.0, *) { Runtime.shared.enable(config) }
    }

    /// A view controller hosting the inspector UI, or `nil` when the inspector isn't available (below
    /// iOS 15, or the release gate rejected this build). The `nil` return is the gate's only signal —
    /// hosts must not force-unwrap.
    @MainActor
    public static func makeViewController() -> UIViewController? {
        guard #available(iOS 15.0, *) else { return nil }
        return Runtime.shared.makeViewController()
    }

    /// Present the inspector modally from `presenter`. A no-op when unavailable.
    @MainActor
    public static func present(from presenter: UIViewController) {
        if #available(iOS 15.0, *) { Runtime.shared.present(from: presenter) }
    }

    /// Dismiss the inspector if it is showing.
    @MainActor
    public static func dismiss() {
        if #available(iOS 15.0, *) { Runtime.shared.dismiss() }
    }
}
