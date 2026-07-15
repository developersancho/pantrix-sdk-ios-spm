//
//  View+TrackScreen.swift
//  PantrixSwiftUI
//
//  Created by developersancho on 8.07.2026.
//

import SwiftUI
import PantrixCore

public extension View {
    /// Reports this SwiftUI screen to Pantrix when it appears — the SwiftUI counterpart of the
    /// automatic UIKit view-controller tracking (which can't see SwiftUI screens). Subsequent events
    /// are attributed to it.
    ///
    /// ```swift
    /// HomeView()
    ///     .trackScreen("Home")
    /// ```
    ///
    /// From iOS 14 the screen is re-reported when `name` changes on an already-visible view (Compose's
    /// `LaunchedEffect(name)` behaves the same way). On iOS 13 `onAppear` fires once per appearance and
    /// a later `name` change is not picked up — give the view a `.id(name)` if you need that.
    func trackScreen(_ name: String) -> some View {
        modifier(TrackScreenModifier(name: name))
    }
}

/// A `ViewModifier` rather than a bare `onAppear` chain: the availability branch for the iOS 14
/// name-change path has to live inside a `@ViewBuilder` body, so the public modifier above can stay
/// unconditionally available at the package's iOS 13 floor.
internal struct TrackScreenModifier: ViewModifier {

    let name: String

    func body(content: Content) -> some View {
        reportingNameChanges(content.onAppear { Pantrix.trackSwiftUIScreen(name) })
    }

    /// `onChange(of:)` is iOS 14. Below that a name change on an already-visible view goes unreported —
    /// the appearance itself is already covered by `onAppear` above.
    @ViewBuilder
    private func reportingNameChanges(_ content: some View) -> some View {
        if #available(iOS 14, *) {
            content.onChange(of: name) { Pantrix.trackSwiftUIScreen($0) }
        } else {
            content
        }
    }
}
