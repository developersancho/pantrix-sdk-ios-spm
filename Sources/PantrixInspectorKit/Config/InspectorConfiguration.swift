//
//  InspectorConfiguration.swift
//  Pantrix
//
//  Knobs for the on-device inspector. Lives in `PantrixInspectorKit` (not the view target) and carries
//  NO `@available`, on purpose: it appears in `PantrixInspector.enable(_ config:)`'s signature, and an
//  annotated type in an un-annotated signature would drag the whole facade above the package's iOS 13
//  floor. So the type is iOS 13-available even though the UI that reads it is iOS 15+ (§4c of the port
//  plan). All fields default to the safest value — the inspector does nothing a host didn't ask for.
//

import Foundation

public struct InspectorConfiguration: Sendable {
    /// Let the inspector activate in a build that is NOT debuggable (no `get-task-allow`). Off by default,
    /// so a shipped App Store build never shows it. The one documented way to see the inspector in a
    /// TestFlight QA build, where `get-task-allow` is absent (§4a) — a deliberate opt-in, not an escape
    /// hatch. Consumed by the release gate (Phase 2).
    public var allowsInReleaseBuilds: Bool = false

    /// Show a draggable floating bubble that opens the inspector. Off by default. Consumed in Phase 6.
    public var showsFloatingBubble: Bool = false

    /// Open the inspector on a device shake. Off by default. Consumed in Phase 6.
    public var enablesShakeToOpen: Bool = false

    public init() {}
}
