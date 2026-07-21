//
//  ReleaseGate.swift
//  Pantrix
//
//  The impure half of the release gate (§4a): probes whether this is a development build, then defers the
//  decision to the Kit's `InspectorAvailability.decide` (which is where the logic is tested). A build is a
//  dev context on the Simulator, or when it carries the `get-task-allow` entitlement — read from the
//  embedded provisioning profile. App Store and TestFlight builds have neither, so the inspector stays dark
//  there unless the host explicitly sets `allowsInReleaseBuilds`.
//
//  iOS 15-gated to satisfy the view-target availability rule; it has no iOS 15 dependency of its own but is
//  only ever reached from `Runtime`.
//

import Foundation
import PantrixInspectorKit

@available(iOS 15.0, *)
struct ReleaseGate {
    let isSimulator: Bool
    let hasGetTaskAllow: Bool

    init() {
        #if targetEnvironment(simulator)
        self.isSimulator = true
        #else
        self.isSimulator = false
        #endif
        self.hasGetTaskAllow = Self.readGetTaskAllow()
    }

    /// Test seam — inject the probe results directly.
    init(isSimulator: Bool, hasGetTaskAllow: Bool) {
        self.isSimulator = isSimulator
        self.hasGetTaskAllow = hasGetTaskAllow
    }

    func isAvailable(allowsInReleaseBuilds: Bool) -> Bool {
        InspectorAvailability.decide(
            isSimulator: isSimulator,
            hasGetTaskAllow: hasGetTaskAllow,
            allowsInReleaseBuilds: allowsInReleaseBuilds
        )
    }

    /// Reads `get-task-allow` from `embedded.mobileprovision`. Absent (App Store / TestFlight) → false. The
    /// profile is a CMS blob with an embedded XML plist; we slice out the `<plist>…</plist>` and read the
    /// entitlement. Best-effort — any parsing failure is treated as "not a dev build".
    private static func readGetTaskAllow() -> Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .isoLatin1),
              let start = raw.range(of: "<plist"),
              let end = raw.range(of: "</plist>") else { return false }
        let plistSlice = String(raw[start.lowerBound..<end.upperBound])
        guard let plistData = plistSlice.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return false }
        return entitlements["get-task-allow"] as? Bool ?? false
    }
}
