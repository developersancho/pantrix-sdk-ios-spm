//
//  PantrixInteractions.swift
//  PantrixSwiftUI
//
//  Created by developersancho on 15.07.2026.
//

import PantrixCore

/// Attribute keys the interaction helpers attach to the events.
internal enum PantrixInteractions {
    /// Attribute key carrying the developer-supplied element name.
    static let element = "element"
    /// Attribute key carrying the resting scroll offset, in points.
    static let scrollOffset = "scrollOffset"
}

/// The attributes for one interaction: the caller's `metadata`, plus the element name.
///
/// The SDK's `element` key is applied **last**, so it wins over a caller who passes their own
/// `"element"` — the element name is the SDK's to set, and cannot be spoofed from a call site.
internal func interactionAttributes(element: String, metadata: [String: Any] = [:]) -> [String: Any] {
    var attributes = metadata
    attributes[PantrixInteractions.element] = element
    return attributes
}

/// The attributes for a settled scroll: the element name and the resting offset, nothing else
/// (Android's `scrollOffsetEvent` takes no metadata either).
internal func scrollAttributes(element: String, scrollOffset: Int) -> [String: Any] {
    [
        PantrixInteractions.element: element,
        PantrixInteractions.scrollOffset: scrollOffset,
    ]
}

/// Records one interaction through `Pantrix.trackInteraction`. Extracted from the modifiers so the
/// event composition (type + element + metadata) is unit-testable without a SwiftUI runtime; `track`
/// is the injectable seam, defaulting to the real facade.
internal func emitInteraction(
    _ type: InteractionType,
    element: String,
    metadata: [String: Any] = [:],
    track: (InteractionType, [String: Any]) -> Void = { Pantrix.trackInteraction($0, attributes: $1) }
) {
    track(type, interactionAttributes(element: element, metadata: metadata))
}

/// Records a settled scroll. Separate from `emitInteraction` because a scroll carries the resting
/// offset instead of caller metadata (again mirroring Android, whose scroll helper takes no metadata).
internal func emitScroll(
    element: String,
    scrollOffset: Int,
    track: (InteractionType, [String: Any]) -> Void = { Pantrix.trackInteraction($0, attributes: $1) }
) {
    track(.scroll, scrollAttributes(element: element, scrollOffset: scrollOffset))
}

/// Emit-only interaction reporting: one-liners you call from inside handlers you already own, when
/// the `View` modifiers don't reach — a `Button` whose action you'd rather not wrap, a gesture the
/// SDK has no modifier for, a UIKit callback bridged into SwiftUI.
///
/// Each function emits exactly what its modifier counterpart emits, so payloads stay identical
/// whichever route you take:
///
/// ```swift
/// Button {
///     PantrixTrack.tap("save_button")
///     viewModel.save()
/// } label: {
///     Text("Save")
/// }
/// ```
///
/// Only the names (and any metadata) you pass leave the device. Every call is a silent no-op until
/// the SDK is initialized.
public enum PantrixTrack {

    /// Reports a `ui_click` on `name`. The modifier counterparts are `trackedTap` / `View.trackTap`.
    public static func tap(_ name: String, metadata: [String: Any] = [:]) {
        emitInteraction(.click, element: name, metadata: metadata)
    }

    /// Reports a `ui_long_click` on `name`. The modifier counterpart is `View.trackTaps`.
    public static func longPress(_ name: String, metadata: [String: Any] = [:]) {
        emitInteraction(.longClick, element: name, metadata: metadata)
    }

    /// Reports a settled `ui_scroll` on `name` at `offset` (points). The modifier counterpart is
    /// `View.trackScroll`, which detects the settle for you — prefer it unless you already track the
    /// offset yourself.
    public static func scroll(_ name: String, offset: Int) {
        emitScroll(element: name, scrollOffset: offset)
    }

    /// Reports a `ui_hover` on `name` (pointer entered). The modifier counterpart is `View.trackHover`.
    public static func hover(_ name: String) {
        emitInteraction(.hover, element: name)
    }

    /// Reports a `ui_focus` on `name` (focus gained). The modifier counterpart is `View.trackFocus`.
    public static func focus(_ name: String) {
        emitInteraction(.focus, element: name)
    }

    /// Reports a `ui_drag` on `name` (a drag started). The modifier counterpart is `View.trackDrag`.
    public static func drag(_ name: String) {
        emitInteraction(.drag, element: name)
    }
}
