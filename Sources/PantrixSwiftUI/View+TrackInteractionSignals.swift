//
//  View+TrackInteractionSignals.swift
//  PantrixSwiftUI
//
//  Created by developersancho on 15.07.2026.
//

import SwiftUI
import PantrixCore

// Android exposes hover, focus and drag through ONE entry point — `TrackInteractions(name,
// interactionSource)` — because Compose has a single read-only `Flow<Interaction>` to observe. SwiftUI
// has no such bus: there is no way to watch an existing view's hover/focus/drag without ATTACHING
// something to its gesture graph. So the one Compose helper becomes three separate modifiers here,
// each with its own availability floor, and each leading-edge only (enter/gain/start — never the
// matching exit/release, exactly as Android drops `HoverInteraction.Exit` etc.). None takes metadata,
// matching Android's `TrackInteractions` (element only).

/// Reports `ui_drag`'s "a drag started" edge exactly once per gesture. Compose gets this free from
/// `DragInteraction.Start` (one Start per gesture); a SwiftUI `DragGesture.onChanged` fires every
/// frame, so this latch reproduces the leading edge. Held in `@State`, reset on gesture end.
@MainActor
internal final class DragEdgeLatch {
    private var fired = false

    /// True the first time it's called after arming; false until `reset()`.
    func arm() -> Bool {
        guard !fired else { return false }
        fired = true
        return true
    }

    func reset() { fired = false }
}

/// A leading-edge handler for a `Bool` signal (hover-entered, focus-gained): emits `type` for `name`
/// when the flag goes true, ignores false. `track` is the injectable seam. Extracted so the emit
/// decision is unit-testable — the modifiers below only wire it into `onHover` / `onChange`.
@MainActor
internal func boolEdgeHandler(
    _ type: InteractionType,
    name: String,
    track: @escaping (InteractionType, [String: Any]) -> Void = { Pantrix.trackInteraction($0, attributes: $1) }
) -> (Bool) -> Void {
    { isActive in
        if isActive { emitInteraction(type, element: name, track: track) }
    }
}

/// Emits `ui_drag` once per gesture via the latch — the body of the drag's `onChanged`, kept
/// value-free (the gesture value is discarded) so it's unit-testable without a `DragGesture.Value`,
/// which has no public initializer.
@MainActor
internal func emitDragStart(
    name: String,
    latch: DragEdgeLatch,
    track: @escaping (InteractionType, [String: Any]) -> Void = { Pantrix.trackInteraction($0, attributes: $1) }
) {
    if latch.arm() { emitInteraction(.drag, element: name, track: track) }
}

/// The handler `trackedEditingChanged` returns: emits `ui_focus` on the false→true edit edge, then
/// forwards to the developer's action. `track` is the injectable seam.
@MainActor
internal func editingChangedHandler(
    _ name: String,
    track: @escaping (InteractionType, [String: Any]) -> Void = { Pantrix.trackInteraction($0, attributes: $1) },
    perform action: ((Bool) -> Void)?
) -> (Bool) -> Void {
    { isEditing in
        if isEditing { emitInteraction(.focus, element: name, track: track) }
        action?(isEditing)
    }
}

public extension View {

    /// Reports `ui_hover` when a pointer enters this view (iPad pointer / Mac Catalyst) — the hover
    /// slice of Android's `TrackInteractions`. Leading edge only; the pointer leaving is not reported.
    ///
    /// `.onHover` is iOS 13.4, so this is a **no-op on iOS 13.0–13.3**. Only `name` leaves the device.
    @MainActor
    func trackHover(_ name: String) -> some View {
        modifier(TrackHoverModifier(name: name))
    }

    /// Reports `ui_drag` when a drag gesture starts on this view — the drag slice of Android's
    /// `TrackInteractions`. Emitted once per gesture (leading edge), never per frame.
    ///
    /// Uses `simultaneousGesture`, NOT `gesture`, so it does **not** steal an enclosing `ScrollView`'s
    /// scrolling — a naive `.gesture(DragGesture())` would break the host app's scroll. Only `name`
    /// leaves the device.
    ///
    /// - Parameters:
    ///   - name: stable element name, sent as the event's `element` attribute.
    ///   - minimumDistance: how far the drag must move before it counts (and reports).
    @MainActor
    func trackDrag(_ name: String, minimumDistance: CGFloat = 10) -> some View {
        modifier(TrackDragModifier(name: name, minimumDistance: minimumDistance))
    }

    /// Reports `ui_focus` when `isFocused` goes true — the focus slice of Android's `TrackInteractions`.
    /// You pass the focus flag you already have (from `@FocusState` on iOS 15, or your own state).
    ///
    /// iOS 13 has no general focus API and `onChange` is iOS 14, so this is a **no-op below iOS 14**.
    /// For a `TextField` on iOS 13 use `trackedEditingChanged` instead. Leading edge only; losing focus
    /// is not reported. Only `name` leaves the device.
    @MainActor
    func trackFocus(_ name: String, isFocused: Bool) -> some View {
        modifier(TrackFocusModifier(name: name, isFocused: isFocused))
    }
}

/// Wraps a `TextField`'s `onEditingChanged` with `ui_focus` tracking on the edit-begins edge, then
/// forwards to your action — the one focus signal available at iOS 13.
///
/// ```swift
/// TextField("Email", text: $email, onEditingChanged: trackedEditingChanged("email_field"))
/// ```
///
/// Emits `ui_focus` when editing begins (not when it ends). Only `name` leaves the device. No-op until
/// the SDK is initialized.
///
/// - Parameters:
///   - name: stable element name, sent as the event's `element` attribute.
///   - action: your own `onEditingChanged` handler, run after the event is recorded.
/// - Returns: an `onEditingChanged` handler that records `ui_focus`, then runs `action`.
@MainActor
public func trackedEditingChanged(
    _ name: String,
    perform action: ((Bool) -> Void)? = nil
) -> (Bool) -> Void {
    editingChangedHandler(name, perform: action)
}

// MARK: - Modifiers (thin shells; the emit logic lives in the handlers above)

internal struct TrackHoverModifier: ViewModifier {
    let name: String

    // AnyView (not @ViewBuilder) on purpose: a `@ViewBuilder` `if #available` needs
    // `buildLimitedAvailability`, which is iOS 14+, so it can't back a 13.4 gate at an iOS 13 floor.
    // Erasing both branches to AnyView sidesteps the availability-erasure machinery entirely.
    func body(content: Content) -> some View {
        if #available(iOS 13.4, *) {
            return AnyView(content.onHover(perform: boolEdgeHandler(.hover, name: name)))
        } else {
            return AnyView(content)
        }
    }
}

internal struct TrackDragModifier: ViewModifier {
    let name: String
    let minimumDistance: CGFloat

    @State private var latch = DragEdgeLatch()

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: minimumDistance)
                .onChanged { _ in emitDragStart(name: name, latch: latch) }
                .onEnded { _ in latch.reset() }
        )
    }
}

internal struct TrackFocusModifier: ViewModifier {
    let name: String
    let isFocused: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 14, *) {
            content.onChange(of: isFocused, perform: boolEdgeHandler(.focus, name: name))
        } else {
            content
        }
    }
}
