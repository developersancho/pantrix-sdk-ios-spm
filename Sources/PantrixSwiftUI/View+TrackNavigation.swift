//
//  View+TrackNavigation.swift
//  PantrixSwiftUI
//
//  Created by developersancho on 15.07.2026.
//

import SwiftUI
import PantrixCore

/// Lets a navigation route supply its own Pantrix screen name. Conform your route type and return a
/// stable, PII-free name per case — this is the SwiftUI answer to Android's `NavKey` type name, and
/// the only way to name an `enum`-with-associated-values route without reflecting over (and leaking)
/// its associated values.
///
/// ```swift
/// enum Route: Hashable, PantrixScreenNameProviding {
///     case home
///     case profile(userId: String)   // the id must NEVER appear in the screen name
///     var pantrixScreenName: String {
///         switch self {
///         case .home: return "Home"
///         case .profile: return "Profile"   // name the case, not the value
///         }
///     }
/// }
/// ```
public protocol PantrixScreenNameProviding {
    /// A stable screen name for this route. Do not include ids, tokens, or other argument values.
    var pantrixScreenName: String { get }
}

/// De-duplicating screen reporter behind `trackNavigation`. Android gets de-dup for free from
/// `LaunchedEffect(current)` re-keying; SwiftUI's `onChange` can fire with an unchanged top entry
/// (e.g. a deeper push then pop back), so `lastTracked` suppresses consecutive duplicates explicitly.
/// `track` is the injectable seam (defaults to the real screen path); extracted so the whole reporter
/// is unit-testable with no SwiftUI and no initialized SDK.
@MainActor
internal final class NavigationScreenReporter {

    private var lastTracked: String?
    private let track: (String) -> Void

    init(track: @escaping (String) -> Void = { Pantrix.trackSwiftUIScreen($0) }) {
        self.track = track
    }

    /// Reports the top entry's name. Mirrors Android's `LaunchedEffect(current)`: the state advances on
    /// every change of the top entry — INCLUDING to nil (an empty stack) — but a name is emitted only
    /// for a non-nil entry. So a pop to root then a push back to the same screen re-emits it (the top
    /// genuinely changed twice), while a top that stays put is suppressed.
    func report(_ name: String?) {
        guard name != lastTracked else { return }
        lastTracked = name
        if let name { track(name) }
    }
}

@available(iOS 16, *)
public extension View {

    /// Reports each `NavigationStack` destination as a `screen_view` (category `SWIFTUI`) as the top of
    /// `path` changes — the SwiftUI counterpart of Android's `PantrixScreenNavTracking(backStack)`.
    /// Each route names itself via `PantrixScreenNameProviding`, so no argument value ever leaves the
    /// device. Attach once, next to the stack:
    ///
    /// ```swift
    /// NavigationStack(path: $path) { … }
    ///     .trackNavigation(path: path)
    /// ```
    ///
    /// `NavigationStack(path:)` is iOS 16, and nothing before it reports a destination change, so this
    /// is iOS 16+. A type-erased `NavigationPath` is NOT supported (it exposes only `count`, not its
    /// elements) — use a typed `[Route]`. Consecutive duplicate destinations are de-duplicated.
    func trackNavigation<Element: Hashable & PantrixScreenNameProviding>(path: [Element]) -> some View {
        modifier(TrackNavigationModifier(path: path, screenName: { $0.pantrixScreenName }))
    }

    /// `trackNavigation(path:)` for routes that are a distinct TYPE per screen (Android's `NavKey`
    /// shape): the screen name is the element's type name (e.g. `ProfileRoute`), never its values.
    ///
    /// Prefer the `PantrixScreenNameProviding` overload for the idiomatic single-`enum` route — for
    /// that shape every case shares one type, so `type(of:)` would report the same name for all
    /// screens. Only `name`s leave the device; associated values are never reflected over.
    func trackNavigation<Element: Hashable>(path: [Element]) -> some View {
        modifier(TrackNavigationModifier(path: path, screenName: { String(describing: type(of: $0)) }))
    }
}

/// Observes the top of the path and funnels it through `NavigationScreenReporter`. Reports the initial
/// destination on appear (Android's `LaunchedEffect` runs at first composition too) and every change
/// after.
@available(iOS 16, *)
internal struct TrackNavigationModifier<Element: Hashable>: ViewModifier {

    let path: [Element]
    let screenName: (Element) -> String

    @State private var reporter = NavigationScreenReporter()

    func body(content: Content) -> some View {
        content
            .onAppear { reporter.report(path.last.map(screenName)) }
            .onChange(of: path) { newPath in reporter.report(newPath.last.map(screenName)) }
    }
}
