//
//  InspectorFormatters.swift
//  Pantrix
//
//  All time parsing + display formatting, in ONE place, pinned to `en_US_POSIX` so the inspector reads the
//  same on a device set to any locale. The view target does no formatting (§4h) — it calls these. The
//  ISO-8601 parser is cached (creating one is expensive) and tries fractional seconds first, then falls
//  back to whole seconds, matching what the SDK writes for `event_date`.
//

import Foundation

public enum InspectorFormatters {

    // A shared ISO-8601 parser with fractional seconds, and a plain one for the fallback. `ISO8601DateFormatter`
    // is not `Sendable`, but parsing doesn't mutate it and these are never reconfigured after creation, so
    // sharing is safe — asserted with `nonisolated(unsafe)`.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoWhole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses an SDK `event_date` string. Tries fractional seconds, then whole seconds.
    public static func date(fromISO string: String) -> Date? {
        isoFractional.date(from: string) ?? isoWhole.date(from: string)
    }

    /// Epoch milliseconds for an SDK date string, or `nil` if it can't be parsed. Used by
    /// [LaunchScopedEvent] to place an `app_exit` row in time.
    public static func epochMillis(fromISO string: String) -> Int64? {
        guard let date = date(fromISO: string) else { return nil }
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    // MARK: - Display formatting (locale-independent)

    /// A short local wall-clock rendering of an SDK date string (e.g. "10:11:14.858"), or the raw string if
    /// it can't be parsed — never a locale-dependent format.
    nonisolated(unsafe) private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    public static func clock(fromISO string: String) -> String {
        guard let date = date(fromISO: string) else { return string }
        return clockFormatter.string(from: date)
    }

    /// A human duration from milliseconds: "820ms", "3.4s", "2m 05s", "1h 02m".
    public static func duration(millis: Int64) -> String {
        if millis < 1000 { return "\(millis)ms" }
        let totalSeconds = Double(millis) / 1000.0
        if totalSeconds < 60 { return String(format: "%.1fs", totalSeconds) }
        let s = Int(totalSeconds.rounded())
        if s < 3600 { return String(format: "%dm %02ds", s / 60, s % 60) }
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }

    /// A byte size, binary units, from a KB value (the SDK stores memory in KB): "512 KB", "40.6 MB".
    public static func size(kilobytes: Int64) -> String {
        size(bytes: kilobytes * 1024)
    }

    /// A byte size, binary units: "820 B", "12.5 KB", "40.6 MB", "1.2 GB".
    public static func size(bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == 0 { return "\(bytes) B" }
        return String(format: "%.1f %@", value, units[unit])
    }
}
