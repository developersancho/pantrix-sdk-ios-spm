//
//  ShakeMath.swift
//  Pantrix
//
//  The pure shake test (Android `FeedbackShakeDetector` parity): the magnitude of the raw accelerometer
//  vector, and whether it clears the configured threshold. Raw acceleration includes gravity, so the device
//  reads ~1g at rest and a threshold of ~2.5g means "a real shake, not just being held". Kept in the Kit so
//  the threshold arithmetic is tested; `FeedbackMotionShake` in the view target only feeds it `CMMotionManager`
//  samples and debounces the hits.
//

import Foundation

public enum ShakeMath {
    /// Euclidean magnitude of an acceleration vector (in g).
    public static func magnitude(x: Double, y: Double, z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// True when the sample's magnitude clears `threshold` (in g).
    public static func isShake(x: Double, y: Double, z: Double, threshold: Double) -> Bool {
        magnitude(x: x, y: y, z: z) > threshold
    }
}
