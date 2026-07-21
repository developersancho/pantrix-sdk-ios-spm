//
//  PantrixCrash.swift
//  PantrixCrash
//
//  The opt-in crash-reporting add-on (Android's `pantrix-crash` analogue). It captures fatal crashes on
//  device and reports them on the NEXT launch through `Pantrix.reportCrash`. Shipped as SOURCE (like
//  PantrixSwiftUI / PantrixAlamofire) and NOT re-exported by the `Pantrix` umbrella — crash handlers grab
//  process-global signal / Mach state and must never auto-install.
//
//  Phase 3 (this file): scaffolding — the module builds, links the C layer and exposes `enable()`.
//  The next-launch record drain + reporting lands in a later phase (the C handlers are still stubs).
//

import Foundation
import PantrixCrashC
import PantrixCore

/// Opt-in fatal-crash reporting. Call `PantrixCrash.enable()` once, right after
/// `Pantrix.initialize(...)`, to arm crash capture. Requires the `PantrixCrash` product.
///
/// ```swift
/// Pantrix.initialize(with: config)
/// PantrixCrash.enable()
/// ```
public enum PantrixCrash {

    /// Arms crash capture. First reports any crash persisted on the previous launch (reading each record,
    /// forwarding it via `Pantrix.reportCrash`, then deleting it), then installs the handlers for this
    /// run. Gated on `Pantrix.isCrashReportingEnabled` (the `enableCrashReporting` config), so a host with
    /// a primary crash reporter — or a remote opt-out — installs nothing. Call once, early, after
    /// `Pantrix.initialize`.
    public static func enable() {
        guard Pantrix.isCrashReportingEnabled else { return }
        crashCounter.set(drainPendingRecords(in: recordDirectory))
        // Tell the SDK the drain is done: "no crash was reported" is only a signal once a crash source has
        // actually looked. This is what lets the app_exit inference separate a crash from an OOM.
        Pantrix._noteCrashDrainComplete()
        // Start staging the crash-time session + screen (primes immediately) BEFORE installing handlers,
        // so a crash right after install already has the current attribution to record.
        Pantrix._setCrashContextObserver(contextForwarder)
        pantrix_crash_bic_start()
        recordDirectory.withCString { pantrix_crash_install($0) }
    }

    /// How many crash records the most recent `enable()` drained and reported this launch — i.e. crashes
    /// captured on the PREVIOUS run. `0` means nothing was pending (no crash last run, or the crash was
    /// never recorded — e.g. it was tested under the Xcode debugger, which intercepts the fault). Useful as
    /// a quick "did capture work?" signal.
    public static var lastReportedCrashCount: Int { crashCounter.get() }

    private static let crashCounter = Counter()

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func get() -> Int { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ newValue: Int) { lock.lock(); defer { lock.unlock() }; value = newValue }
    }

    /// Removes the crash handlers this module installed and restores the previous ones, and stops staging
    /// the session/screen context.
    public static func disable() {
        pantrix_crash_uninstall()
        Pantrix._setCrashContextObserver(nil)
    }

    /// Forwards session/screen changes from PantrixCore into the async-signal-safe C staging buffers, so a
    /// crash captured this run records the session + screen that were current at crash time. Retained for
    /// the process by the SDK's relay while registered.
    private static let contextForwarder = CrashContextForwarder()

    private final class CrashContextForwarder: PantrixCrashContextObserver {
        func onSessionChanged(sessionId: String) {
            pantrixcrash_set_session(sessionId)
        }
        func onForegroundChanged(_ foreground: Bool) {
            pantrixcrash_set_foreground(foreground)
        }
        func onScreenChanged(_ screen: PantrixCrashScreenSnapshot?) {
            guard let screen else {
                pantrixcrash_set_screen("", "", "", "", -1, -1)
                return
            }
            pantrixcrash_set_screen(
                screen.id, screen.name, screen.category, screen.enteredAt ?? "",
                screen.loadTime ?? -1, screen.duration ?? -1
            )
        }
    }

    /// Reads every pending `.pcrx` record in `directory`, reports it via `Pantrix.reportCrash`, and
    /// deletes it — even if it can't be parsed, so a corrupt record never piles up. Returns how many were
    /// reported. Internal for tests.
    @discardableResult
    static func drainPendingRecords(in directory: String) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return 0 }
        var reported = 0
        for file in files where file.hasSuffix(".pcrx") {
            let path = directory + "/" + file
            defer { try? FileManager.default.removeItem(atPath: path) }
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let report = CrashRecordReader.read(data) {
                Pantrix.reportCrash(report)
                reported += 1
            }
        }
        return reported
    }

    /// Where crash records are written at crash time and read on the next launch. Under the app's
    /// caches directory (survives relaunch, excluded from most backups), created on demand.
    static var recordDirectory: String {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("com.pantrix.crash", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
}
