//
//  DeviceAppInfo.swift
//  Pantrix
//
//  The device + app facts appended to a feedback e-mail (Android `getDeviceInfo`/`getAppInfo` parity). Impure
//  (reads `UIDevice`/`Bundle`), so it lives in the exempt view target; the pure assembly that turns these into
//  the e-mail body is `EmailComposition` in the Kit. Deliberately omits `UIDevice.name` — it's user-assigned
//  PII (and iOS 16+ returns a generic value without entitlement), and nothing here needs it.
//

import UIKit

@available(iOS 15.0, *)
enum DeviceAppInfo {
    static func device() -> [String: String] {
        let d = UIDevice.current
        return [
            "model": d.model,
            "systemName": d.systemName,
            "systemVersion": d.systemVersion,
        ]
    }

    static func app() -> [String: String] {
        let info = Bundle.main.infoDictionary
        return [
            "bundleId": Bundle.main.bundleIdentifier ?? "unknown",
            "version": info?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": info?["CFBundleVersion"] as? String ?? "unknown",
        ]
    }
}
