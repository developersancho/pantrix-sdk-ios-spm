//
//  OverlayPresentation.swift
//  Pantrix
//
//  Pure decision for "which window do we present the inspector on?" — kept in the Kit so the rule is
//  unit-tested away from UIKit. The trap it guards against (§4d): the floating-bubble overlay lives in its
//  OWN `UIWindow`, and that window is part of the scene's `windows`. Tapping the bubble can make the overlay
//  the key window, so a naive "present on the key window" picks the overlay — whose `hitTest` returns nil
//  everywhere but the bubble, so the presented inspector receives NO touches. The host window must therefore
//  be chosen by EXCLUDING the overlay, never by key-status alone.
//

public struct OverlayWindowCandidate: Equatable, Sendable {
    public let isKey: Bool
    public let isOverlay: Bool
    public init(isKey: Bool, isOverlay: Bool) {
        self.isKey = isKey
        self.isOverlay = isOverlay
    }
}

public enum OverlayPresentation {
    /// Index of the window to present the inspector on: the key window that is NOT the overlay, else the
    /// first non-overlay window. `nil` only when every candidate is the overlay (nothing to present on).
    public static func hostIndex(_ candidates: [OverlayWindowCandidate]) -> Int? {
        if let key = candidates.firstIndex(where: { $0.isKey && !$0.isOverlay }) { return key }
        return candidates.firstIndex(where: { !$0.isOverlay })
    }
}
