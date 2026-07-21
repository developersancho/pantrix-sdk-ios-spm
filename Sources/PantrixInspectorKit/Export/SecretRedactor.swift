//
//  SecretRedactor.swift
//  Pantrix
//
//  Masks the VALUES of JSON body fields whose KEY looks sensitive, before a body leaves the device in an
//  export. This is the body-side counterpart to `HeaderRedactor` (which does headers), and BOTH are applied
//  to every export path unconditionally (§4g). Marker list ported from the Android inspector's prefs
//  redactor. Matches by case-insensitive key substring, recursively through nested objects/arrays.
//
//  A non-JSON body has no key structure to redact, so it passes through unchanged — a documented limit; the
//  header layer and the SDK's own capture-time blocklist still apply.
//

import Foundation

public enum SecretRedactor {
    static let redactedPlaceholder = "***REDACTED***"

    static let secretMarkers = [
        "password", "passwd", "pwd", "token", "secret", "api_key", "apikey",
        "auth", "credential", "session", "private", "otp", "db_key",
        "jwt", "bearer", "cookie", "signature", "salt", "passphrase",
        "cvv", "cvc", "ssn", "card", "iban",
    ]

    public static func isSecret(key: String) -> Bool {
        let lower = key.lowercased()
        return secretMarkers.contains { lower.contains($0) }
    }

    /// Redacts sensitive-keyed values in a JSON body. Non-JSON (or unparseable) input returns unchanged.
    public static func redactedJSON(_ body: String) -> String {
        guard !body.isEmpty,
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return body
        }
        let redacted = redact(object)
        guard let out = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys, .fragmentsAllowed]),
              let string = String(data: out, encoding: .utf8) else {
            return body
        }
        return string
    }

    private static func redact(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, val) in dict {
                out[key] = isSecret(key: key) ? redactedPlaceholder : redact(val)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map { redact($0) }
        }
        return value
    }
}
