//
//  NetworkExport.swift
//  Pantrix
//
//  Resolves a raw `NetworkRecord` into export-ready fields ONCE — decoding headers, applying BOTH redactors
//  (§4g), and labelling each body/header with its `CaptureAvailability` (§4f) — so all five export builders
//  (cURL / HAR / CSV / JSON / TXT) inherit the same redaction and the same honesty labels. A blank field is
//  never silently blank: the label says whether capture was off, the body was empty, or it was redacted.
//

import Foundation

/// What the host enabled at capture time. `nil` = unknown (the inspector can't always read the live
/// config), which the resolver treats as "not provably disabled" — an empty field then reads as genuinely
/// empty, not as capture-disabled.
public struct CaptureConfig: Sendable, Equatable {
    public var headersEnabled: Bool?
    public var bodyEnabled: Bool?

    public init(headersEnabled: Bool? = nil, bodyEnabled: Bool? = nil) {
        self.headersEnabled = headersEnabled
        self.bodyEnabled = bodyEnabled
    }

    public static let unknown = CaptureConfig()
}

/// A resolved body/header field: the (redacted) value plus why it is what it is.
public struct NetworkExportField: Equatable, Sendable {
    public let value: String
    public let availability: CaptureAvailability

    public var hasContent: Bool { availability.hasContent && !value.isEmpty }

    /// A short parenthetical note for an absent field, or "" when present.
    public var note: String {
        switch availability {
        case .captured, .truncated: return ""
        case .captureDisabled: return "capture disabled"
        case .genuinelyEmpty: return "empty"
        case .redacted: return "redacted"
        case .notCapturableOnIOS(let reason): return reason
        }
    }
}

/// A `NetworkRecord` with headers decoded + redacted and bodies redacted + labelled.
public struct ResolvedNetworkRecord: Equatable, Sendable {
    public let record: NetworkRecord
    public let requestHeaders: [String: String]
    public let responseHeaders: [String: String]
    public let requestBody: NetworkExportField
    public let responseBody: NetworkExportField

    public var method: String { record.method.isEmpty ? "GET" : record.method.uppercased() }
    public var httpVersion: String { ProtocolFormatter.httpVersion(record.networkProtocol) }
    public var statusText: String { HttpStatusText.text(for: Int(record.statusCode)) }

    public static func resolve(_ record: NetworkRecord, config: CaptureConfig = .unknown) -> ResolvedNetworkRecord {
        let reqHeaders = HeaderRedactor.redacted(decodeHeaders(record.requestHeaders))
        let resHeaders = HeaderRedactor.redacted(decodeHeaders(record.responseHeaders))
        return ResolvedNetworkRecord(
            record: record,
            requestHeaders: reqHeaders,
            responseHeaders: resHeaders,
            requestBody: resolveBody(record.requestBody, enabled: config.bodyEnabled),
            responseBody: resolveBody(record.responseBody, enabled: config.bodyEnabled)
        )
    }

    private static func resolveBody(_ raw: String, enabled: Bool?) -> NetworkExportField {
        let availability = CaptureAvailability.classify(value: raw, captureEnabled: enabled ?? true)
        // Redact only content we actually have; an absent field keeps its empty value.
        let value = availability.hasContent ? SecretRedactor.redactedJSON(raw) : ""
        return NetworkExportField(value: value, availability: availability)
    }

    /// Decodes a header JSON string ("{}" / "" / corrupt → empty map). Headers never throw out of an
    /// export — a corrupt blob just yields no headers.
    static func decodeHeaders(_ json: String) -> [String: String] {
        guard !json.isEmpty, json != "{}",
              let data = json.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }
}

/// A ready-to-share file: an in-memory string payload with a filename + UTI. The view wraps it in a
/// `UIActivityViewController` (Phase 3b). Files are written to a temp URL on demand and pruned after >1h.
public struct ShareArtifact: Equatable, Sendable {
    public let filename: String
    public let content: String
    /// A Uniform Type Identifier for the share sheet (e.g. "public.json", "public.plain-text").
    public let uti: String

    public init(filename: String, content: String, uti: String) {
        self.filename = filename
        self.content = content
        self.uti = uti
    }

    public var data: Data { Data(content.utf8) }
}
