//
//  BubbleGeometry.swift
//  Pantrix
//
//  Pure geometry for the floating-bubble overlay (§4d): edge-snap, in-bounds clamping, tap-vs-drag, and
//  touch pass-through. Kept in the Kit so the arithmetic — the part that decides whether a touch opens the
//  inspector or falls through to the host — is unit-tested; the `OverlayWindow` just calls it.
//

import CoreGraphics

public enum BubbleGeometry {
    /// A drag shorter than this (points) counts as a TAP, not a move — so a small finger jitter still opens
    /// the inspector rather than nudging the bubble.
    public static let tapSlop: CGFloat = 8

    /// True when a gesture translation is small enough to be a tap.
    public static func isTap(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) <= tapSlop
    }

    /// Snaps a bubble centre to the nearer horizontal edge and clamps it inside `bounds`, keeping the whole
    /// bubble on-screen (a `margin` inset from the edges).
    public static func snapped(center: CGPoint, bubbleSize: CGSize, in bounds: CGRect, margin: CGFloat = 8) -> CGPoint {
        let halfW = bubbleSize.width / 2
        let halfH = bubbleSize.height / 2
        let minX = bounds.minX + margin + halfW
        let maxX = bounds.maxX - margin - halfW
        let minY = bounds.minY + margin + halfH
        let maxY = bounds.maxY - margin - halfH

        let clampedY = min(max(center.y, minY), maxY)
        // Snap X to whichever side the bubble is closer to.
        let snappedX = center.x < bounds.midX ? minX : maxX
        return CGPoint(x: snappedX, y: clampedY)
    }

    /// Whether a touch at `point` (in the overlay window's coordinate space) lands on the bubble. Outside it,
    /// the window returns `nil` from `hitTest` so the touch falls through to the host.
    public static func hitsBubble(point: CGPoint, bubbleFrame: CGRect) -> Bool {
        bubbleFrame.contains(point)
    }
}
