//
//  HeaderRedactor.swift
//  Pantrix
//
//  Masks the VALUES of sensitive-named HTTP headers before they leave the device in an export (cURL / HAR /
//  CSV / …). The SDK already blocklists headers at capture time; this is a second, name-heuristic layer on
//  export that catches a non-standard auth header the blocklist missed. Matches by case-insensitive name
//  substring; header NAMES are kept (they aid debugging and are rarely sensitive), only the value is
//  replaced. Ported from the Android inspector.
//

import Foundation

public enum HeaderRedactor {
    static let redactedPlaceholder = "***REDACTED***"

    static let sensitiveMarkers = [
        "authorization", "auth", "token", "secret", "api-key", "apikey", "api_key",
        "cookie", "session", "credential", "password", "passwd", "bearer",
        "x-csrf", "x-xsrf", "jwt", "signature", "private-key",
    ]

    public static func isSensitive(name: String) -> Bool {
        let lower = name.lowercased()
        return sensitiveMarkers.contains { lower.contains($0) }
    }

    /// Masks each value whose header NAME matches a sensitive marker; other values pass through.
    public static func redacted(_ headers: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        out.reserveCapacity(headers.count)
        for (name, value) in headers {
            out[name] = isSensitive(name: name) ? redactedPlaceholder : value
        }
        return out
    }
}
