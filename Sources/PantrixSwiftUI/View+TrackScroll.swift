//
//  View+TrackScroll.swift
//  PantrixSwiftUI
//
//  Created by developersancho on 15.07.2026.
//

import SwiftUI
import PantrixCore

/// Names shared by the scroll container and the tracked content.
internal enum PantrixScroll {
    /// The coordinate space `trackScroll` measures the content's offset against. Internal (not a
    /// caller-supplied string) so the container and the content can never disagree on the name.
    static let space = "pantrix.scroll"
}

/// Carries the tracked content's offset up to the modifier. Only changes are delivered (SwiftUI
/// compares `Equatable` values), which is the first half of Android's `distinctUntilChanged`.
internal struct PantrixScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

public extension View {

    /// Marks this `ScrollView` (or `List`) as the coordinate space that `trackScroll` measures against.
    /// Apply it to the SCROLL CONTAINER; apply `trackScroll` to the CONTENT inside it.
    ///
    /// ```swift
    /// ScrollView {
    ///     VStack { /* rows */ }
    ///         .trackScroll("settings_page")
    /// }
    /// .pantrixScrollContainer()
    /// ```
    ///
    /// Without this on the container, `trackScroll` has no named space to measure and reports nothing.
    func pantrixScrollContainer() -> some View {
        coordinateSpace(name: PantrixScroll.space)
    }

    /// Reports a `ui_scroll` interaction each time a scroll gesture settles, tagged with `name` and the
    /// resting scroll offset (points) — the SwiftUI counterpart of Android's `TrackScroll(name, state)`.
    /// One event per gesture, not per frame.
    ///
    /// Apply to the CONTENT of a `ScrollView` that is marked with `pantrixScrollContainer()`:
    ///
    /// ```swift
    /// ScrollView {
    ///     LazyVStack { /* rows */ }
    ///         .trackScroll("product_feed")
    /// }
    /// .pantrixScrollContainer()
    /// ```
    ///
    /// Emits exactly `element` + `scrollOffset` — the same keys as Android's `ScrollState` overload.
    /// (Android's `LazyListState` `firstVisibleItem` has no iOS equivalent and is not emitted.) Only
    /// `name` and the offset leave the device. No-op until the SDK is initialized.
    ///
    /// - Parameters:
    ///   - name: stable element name, sent as the event's `element` attribute.
    ///   - settleAfter: idle time after the last offset change before the gesture counts as settled.
    func trackScroll(_ name: String, settleAfter: TimeInterval = 0.15) -> some View {
        modifier(TrackScrollModifier(name: name, settleAfter: settleAfter))
    }
}

/// Reads the content's offset in the container's coordinate space via a `GeometryReader` background,
/// then funnels changes through a `ScrollSettleDetector` so only settled scrolls emit.
internal struct TrackScrollModifier: ViewModifier {

    let name: String
    let settleAfter: TimeInterval

    /// The detector holds the debounce state across offset changes, so it must survive re-renders —
    /// `@State` keeps one instance per view identity. (`@StateObject` would be iOS 14.)
    @State private var detector = ScrollSettleDetector()

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PantrixScrollOffsetKey.self,
                        // minY grows negative as content scrolls up; negate so offset grows with scroll.
                        value: -proxy.frame(in: .named(PantrixScroll.space)).minY
                    )
                }
            )
            .onPreferenceChange(PantrixScrollOffsetKey.self) { offset in
                detector.report(offset: Int(offset.rounded()), settleAfter: settleAfter) { restingOffset in
                    emitScroll(element: name, scrollOffset: restingOffset)
                }
            }
    }
}
