//
//  View+TrackTap.swift
//  PantrixSwiftUI
//
//  Created by developersancho on 15.07.2026.
//

import SwiftUI
import PantrixCore

/// Wraps a component's own click action with `ui_click` tracking — for `Button`, and anything else
/// that already takes an `action: () -> Void`. Use this instead of `View.trackTap(_:perform:)` for
/// those: `trackTap` installs an `.onTapGesture`, so on a `Button` it would add a *second* handler.
///
/// ```swift
/// Button(action: trackedTap("save_button") { viewModel.save() }) { Text("Save") }
/// ```
///
/// The event is recorded, then `action` runs. Only `name` (and any `metadata`) leaves the device.
/// No-op until the SDK is initialized.
///
/// - Parameters:
///   - name: stable element name, sent as the event's `element` attribute.
///   - metadata: extra attributes to attach to the event.
///   - action: the component's action to run after the event is recorded.
/// - Returns: an action that records `ui_click`, then runs `action`.
@MainActor
public func trackedTap(
    _ name: String,
    metadata: [String: Any] = [:],
    perform action: @escaping () -> Void
) -> () -> Void {
    interactionHandler(.click, name: name, metadata: metadata, perform: action)
}

/// A record-then-run handler: emits `type` for `name`, then runs `action`. Every tap/long-press
/// entry point is built from this, so the whole "compose the event, then forward" behaviour is
/// covered by unit tests that call the returned closure directly — the modifiers below only wire it
/// into a gesture. `track` is the injectable seam (public `trackedTap` binds the real facade).
@MainActor
internal func interactionHandler(
    _ type: InteractionType,
    name: String,
    metadata: [String: Any] = [:],
    track: @escaping (InteractionType, [String: Any]) -> Void = { Pantrix.trackInteraction($0, attributes: $1) },
    perform action: @escaping () -> Void
) -> () -> Void {
    {
        emitInteraction(type, element: name, metadata: metadata, track: track)
        action()
    }
}

public extension View {

    /// Installs an `.onTapGesture` that reports a `ui_click` tagged with `name` (and any `metadata`)
    /// before running `action` — the SwiftUI counterpart of Android's `Modifier.trackClick`. For views
    /// that do NOT already own a tap handler (`Text`, `Image`, a custom row).
    ///
    /// ```swift
    /// Text("Subscribe").trackTap("subscribe_row") { subscribe() }
    /// ```
    ///
    /// Do NOT apply this on top of a `Button` — that installs a second handler; use `trackedTap` there.
    /// Only `name` (and any `metadata`) leaves the device. No-op until the SDK is initialized.
    @MainActor
    func trackTap(
        _ name: String,
        metadata: [String: Any] = [:],
        perform action: @escaping () -> Void
    ) -> some View {
        onTapGesture(perform: interactionHandler(.click, name: name, metadata: metadata, perform: action))
    }

    /// Reports a `ui_click` for taps and a `ui_long_click` for long presses, each tagged with `name`
    /// (and any `metadata`) — the SwiftUI counterpart of Android's `Modifier.trackClicks`.
    ///
    /// ```swift
    /// row.trackTaps("list_item", onLongPress: { showMenu() }) { open() }
    /// ```
    ///
    /// When `onLongPress` is `nil` the long-press gesture is not attached at all and long presses are
    /// not tracked (parity with Android, which installs the long-press wrapper only when the caller
    /// supplies an action). Once a long press fires, the following tap does not — one gesture produces
    /// exactly one event. No-op until the SDK is initialized.
    @MainActor
    @ViewBuilder
    func trackTaps(
        _ name: String,
        metadata: [String: Any] = [:],
        onLongPress: (() -> Void)? = nil,
        perform action: @escaping () -> Void
    ) -> some View {
        if let onLongPress {
            onLongPressGesture(perform: interactionHandler(.longClick, name: name, metadata: metadata, perform: onLongPress))
                .onTapGesture(perform: interactionHandler(.click, name: name, metadata: metadata, perform: action))
        } else {
            onTapGesture(perform: interactionHandler(.click, name: name, metadata: metadata, perform: action))
        }
    }
}
