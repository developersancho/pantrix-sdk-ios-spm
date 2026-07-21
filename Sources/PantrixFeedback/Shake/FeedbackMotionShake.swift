//
//  FeedbackMotionShake.swift
//  Pantrix
//
//  Shake-to-open via CoreMotion (Android `FeedbackShakeDetector` parity). Deliberately NOT the inspector's
//  `-[UIWindow motionEnded:]` swizzle: feedback is a separate product, and a second swizzle would clash with
//  (and clobber) the inspector's hook. CoreMotion touches no swizzle, so both add-ons coexist — the one
//  remaining caveat (both shakes enabled → one shake opens both) is documented, not coded around (§4d).
//
//  The pure "is this a shake" test is `ShakeMath` in the Kit; this class only pumps `CMMotionManager` samples
//  into it and debounces the hits so one physical shake fires once.
//
//  `@preconcurrency import`: CoreMotion's accelerometer handler predates Swift concurrency; the update queue
//  is `.main`, so `MainActor.assumeIsolated` safely re-enters the main actor to touch our state.
//

@preconcurrency import CoreMotion
import Foundation
import PantrixFeedbackKit

@available(iOS 15.0, *)
@MainActor
final class FeedbackMotionShake {
    private let manager = CMMotionManager()
    private var onShake: (() -> Void)?
    private var threshold: Double = 2.5
    private var lastFire = Date.distantPast
    private let cooldown: TimeInterval = 1.0

    /// Begin listening. Idempotent — a second `start` while already active is ignored.
    func start(threshold: Double, onShake: @escaping () -> Void) {
        guard manager.isAccelerometerAvailable, !manager.isAccelerometerActive else { return }
        self.threshold = threshold
        self.onShake = onShake
        manager.accelerometerUpdateInterval = 1.0 / 30.0
        manager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let acceleration = data?.acceleration else { return }
            MainActor.assumeIsolated {
                self?.handle(x: acceleration.x, y: acceleration.y, z: acceleration.z)
            }
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates()
        onShake = nil
    }

    private func handle(x: Double, y: Double, z: Double) {
        guard ShakeMath.isShake(x: x, y: y, z: z, threshold: threshold) else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFire) > cooldown else { return }   // one shake → one fire
        lastFire = now
        onShake?()
    }
}
