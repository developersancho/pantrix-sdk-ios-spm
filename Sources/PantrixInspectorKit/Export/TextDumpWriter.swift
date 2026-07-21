//
//  TextDumpWriter.swift
//  Pantrix
//
//  A human-readable plain-text dump of a request — the fifth export path. Headers/body already redacted;
//  an absent body prints its availability note, not a blank line (§4f).
//

import Foundation

public enum TextDumpWriter {

    public static func build(_ r: ResolvedNetworkRecord) -> String {
        var lines: [String] = []
        lines.append("\(r.method) \(r.record.url)")
        lines.append("\(r.httpVersion) — \(r.record.statusCode) \(r.statusText)")
        lines.append("duration: \(InspectorFormatters.duration(millis: r.record.duration))")
        if !r.record.domainName.isEmpty { lines.append("host: \(r.record.domainName)") }

        lines.append("")
        lines.append("— Request headers —")
        lines.append(contentsOf: headerLines(r.requestHeaders))
        lines.append("")
        lines.append("— Request body —")
        lines.append(bodyBlock(r.requestBody))

        lines.append("")
        lines.append("— Response headers —")
        lines.append(contentsOf: headerLines(r.responseHeaders))
        lines.append("")
        lines.append("— Response body —")
        lines.append(bodyBlock(r.responseBody))

        return lines.joined(separator: "\n")
    }

    public static func artifact(_ r: ResolvedNetworkRecord) -> ShareArtifact {
        ShareArtifact(filename: "request.txt", content: build(r), uti: "public.plain-text")
    }

    private static func headerLines(_ headers: [String: String]) -> [String] {
        headers.isEmpty ? ["(none)"] : headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
    }

    private static func bodyBlock(_ body: NetworkExportField) -> String {
        body.hasContent ? body.value : "(\(body.note))"
    }
}
