//
//  PantrixInspectorNoop.swift
//  Pantrix
//
//  No-op twin of `PantrixInspector` — the iOS analogue of Android's `pantrix-inspector-noop`. It replicates
//  the PUBLIC API of `PantrixInspector` (the `PantrixInspector` facade + `InspectorConfiguration`) as inert
//  stubs, so a host can link THIS product in a Release / App Store build instead of the real
//  `PantrixInspector`. The real inspector's code — and its `PantrixInspectorKit` data layer — then never
//  ship in that binary: zero on-device debug-tool code, zero reverse-engineering surface, zero size.
//
//  SPM has no per-configuration dependency like Gradle's `releaseImplementation`, so the swap is a
//  per-configuration LINK in the host's Xcode target plus a compile guard on the import:
//
//      #if PANTRIX_INSPECTOR              // your own flag, defined only on Debug / QaTest
//      import PantrixInspector            // real
//      #else
//      import PantrixInspectorNoop        // this — inert
//      #endif
//      ...
//      PantrixInspector.enable(InspectorConfiguration())   // identical call site against either module
//
//  Every symbol here mirrors `PantrixInspector` exactly (names, signatures, defaults, `@MainActor`) so the
//  host's call sites compile unchanged whichever module is imported.
//

import UIKit

/// Inert twin of `InspectorConfiguration` — same fields and defaults, no behaviour.
public struct InspectorConfiguration: Sendable {
    public var allowsInReleaseBuilds: Bool = false
    public var showsFloatingBubble: Bool = false
    public var enablesShakeToOpen: Bool = false
    public init() {}
}

/// Inert twin of `PantrixInspector`. Every entry point is a no-op; `isAvailable` is always `false` and
/// `makeViewController()` always returns `nil`, so a host's "Open Inspector" affordance stays hidden.
public enum PantrixInspector {

    @MainActor
    public static var isAvailable: Bool { false }

    @MainActor
    public static func enable(_ config: InspectorConfiguration = .init()) {}

    @MainActor
    public static func makeViewController() -> UIViewController? { nil }

    @MainActor
    public static func present(from presenter: UIViewController) {}

    @MainActor
    public static func dismiss() {}
}
