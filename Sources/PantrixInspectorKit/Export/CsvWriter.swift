//
//  CsvWriter.swift
//  Pantrix
//
//  A per-request summary CSV, RFC-4180 quoted (a field with a comma, quote or newline is wrapped in quotes
//  and its quotes doubled). Bodies aren't dumped here — their availability NOTE is, so the summary is honest
//  about what a fuller export would carry. Ported intent from the Android inspector, with real quote
//  escaping (Android's was unescaped — §1).
//

import Foundation

public enum CsvWriter {
    static let columns = [
        "date", "method", "url", "status", "status_text", "duration_ms", "protocol",
        "request_body", "response_body",
    ]

    public static func build(_ records: [ResolvedNetworkRecord]) -> String {
        var lines = [columns.map(field).joined(separator: ",")]
        for r in records {
            lines.append([
                r.record.eventDate,
                r.method,
                r.record.url,
                String(r.record.statusCode),
                r.statusText,
                String(r.record.duration),
                r.httpVersion,
                bodyCell(r.requestBody),
                bodyCell(r.responseBody),
            ].map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")   // RFC-4180 line ending
    }

    public static func artifact(_ records: [ResolvedNetworkRecord]) -> ShareArtifact {
        ShareArtifact(filename: "pantrix-network.csv", content: build(records), uti: "public.comma-separated-values-text")
    }

    /// The value if present, else its availability note in angle brackets (never a bare blank cell).
    private static func bodyCell(_ body: NetworkExportField) -> String {
        body.hasContent ? body.value : "<\(body.note)>"
    }

    /// RFC-4180: quote a field that contains a comma, double-quote or CR/LF, doubling embedded quotes.
    static func field(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
