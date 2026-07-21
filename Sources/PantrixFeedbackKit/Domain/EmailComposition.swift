//
//  EmailComposition.swift
//  Pantrix
//
//  Pure builders for the feedback e-mail's subject and body (Android `FeedbackSender.sendViaEmail` parity).
//  Kept in the Kit so the string assembly — the part that decides what leaves the device — is unit-tested and
//  deterministic; the impure inputs (the timestamp string, the device/app dictionaries) are produced in the
//  view target and passed in.
//

import Foundation

public enum EmailComposition {
    /// `"<prefix> <timestamp>"`, or just the timestamp when the prefix is blank (Android parity).
    public static func subject(prefix: String, timestamp: String) -> String {
        let p = prefix.trimmingCharacters(in: .whitespaces)
        return p.isEmpty ? timestamp : "\(p) \(timestamp)"
    }

    /// The message, then the device + app info as sorted `key: value` lines. Keys are sorted so the output is
    /// deterministic (testable) regardless of dictionary ordering. An empty message is omitted, not blank.
    public static func body(message: String, deviceInfo: [String: String], appInfo: [String: String]) -> String {
        var lines: [String] = []
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append(trimmed)
            lines.append("")
        }
        lines.append("— Device —")
        lines.append(contentsOf: deviceInfo.keys.sorted().map { "\($0): \(deviceInfo[$0]!)" })
        lines.append("")
        lines.append("— App —")
        lines.append(contentsOf: appInfo.keys.sorted().map { "\($0): \(appInfo[$0]!)" })
        return lines.joined(separator: "\n")
    }
}
