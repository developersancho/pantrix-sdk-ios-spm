//
//  ChartMath.swift
//  Pantrix
//
//  Pure scale + tick + gauge-angle math behind the Canvas charts (§4h: the view draws, the Kit computes).
//  Kept out of the view target so the arithmetic — the part that's easy to get subtly wrong — is tested.
//

import Foundation

/// A linear value→unit scale for a chart axis, with "nice" round ticks.
public struct ChartScale: Equatable, Sendable {
    public let min: Double
    public let max: Double

    /// Builds a scale spanning the values, padded so a flat series still has height. Empty → 0…1.
    public init(values: [Double]) {
        guard let lo = values.min(), let hi = values.max() else {
            self.min = 0; self.max = 1; return
        }
        if lo == hi {
            // A flat line: give it a symmetric band so it doesn't collapse to a point.
            let pad = lo == 0 ? 1 : Swift.abs(lo) * 0.1
            self.min = lo - pad; self.max = hi + pad
        } else {
            self.min = lo; self.max = hi
        }
    }

    public init(min: Double, max: Double) {
        self.min = min
        self.max = Swift.max(max, min + .ulpOfOne)
    }

    /// Maps a value to 0…1 within the scale (clamped).
    public func normalized(_ value: Double) -> Double {
        let span = max - min
        guard span > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, (value - min) / span))
    }

    /// `count` evenly spaced tick values across the scale, inclusive of both ends.
    public func ticks(_ count: Int) -> [Double] {
        guard count > 1 else { return [min] }
        let step = (max - min) / Double(count - 1)
        return (0..<count).map { min + Double($0) * step }
    }
}

/// Angle math for `ArcGauge`: a value's fraction mapped into an arc that starts at 135° and sweeps 270°
/// (the classic open-bottom gauge), clockwise.
public enum GaugeMath {
    public static let startDegrees: Double = 135
    public static let sweepDegrees: Double = 270

    /// The end angle (degrees) for a fraction 0…1 of the sweep.
    public static func endDegrees(fraction: Double) -> Double {
        let clamped = Swift.min(1, Swift.max(0, fraction))
        return startDegrees + sweepDegrees * clamped
    }

    /// Radians for a degree value.
    public static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}
