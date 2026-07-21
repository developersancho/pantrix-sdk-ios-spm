//
//  NetworkDetailViewModel.swift
//  Pantrix
//
//  Prepares one network transaction for the 4-segment detail screen (Overview / Request / Response /
//  Timing) and produces the export artifacts. Resolving the record ONCE (headers decoded + both redactors +
//  availability labels) means the screen and every export show the same redacted, honestly-labelled data.
//

import Foundation

@MainActor
public final class NetworkDetailViewModel: ObservableObject {
    public let resolved: ResolvedNetworkRecord

    public init(record: NetworkRecord, config: CaptureConfig = .unknown) {
        self.resolved = ResolvedNetworkRecord.resolve(record, config: config)
    }

    public var title: String { resolved.record.url }
    public var method: String { resolved.method }
    public var statusCode: Int { Int(resolved.record.statusCode) }
    public var statusText: String { resolved.statusText }

    // MARK: - Segments

    public var overviewRows: [DetailRow] {
        let r = resolved.record
        var rows = [
            DetailRow(key: "method", value: resolved.method),
            DetailRow(key: "url", value: r.url),
            DetailRow(key: "status", value: statusCode == 0 ? "—" : "\(statusCode) \(statusText)"),
            DetailRow(key: "protocol", value: resolved.httpVersion),
            DetailRow(key: "duration", value: InspectorFormatters.duration(millis: r.duration)),
            DetailRow(key: "client", value: r.client),
        ]
        if !r.domainName.isEmpty { rows.append(DetailRow(key: "host", value: r.domainName)) }
        if !r.dnsAddress.isEmpty { rows.append(DetailRow(key: "dns", value: r.dnsAddress)) }
        if !r.failureReason.isEmpty { rows.append(DetailRow(key: "failure", value: r.failureReason)) }
        if !r.failureDescription.isEmpty { rows.append(DetailRow(key: "failure_detail", value: r.failureDescription)) }
        return rows
    }

    public var requestHeaderRows: [DetailRow] { headerRows(resolved.requestHeaders) }
    public var responseHeaderRows: [DetailRow] { headerRows(resolved.responseHeaders) }
    public var requestBody: NetworkExportField { resolved.requestBody }
    public var responseBody: NetworkExportField { resolved.responseBody }

    public var timingRows: [DetailRow] {
        let r = resolved.record
        return [
            DetailRow(key: "start", value: String(r.startTime)),
            DetailRow(key: "end", value: String(r.endTime)),
            DetailRow(key: "duration", value: InspectorFormatters.duration(millis: r.duration)),
        ]
    }

    /// The body pretty-printed for display when it's JSON, otherwise the raw (redacted) text; an absent
    /// body renders its availability note. Formatting stays in the Kit (§4h) — the view only highlights.
    public func bodyDisplay(_ field: NetworkExportField) -> String {
        guard field.hasContent else { return "(\(field.note))" }
        guard let data = field.value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
              let string = String(data: pretty, encoding: .utf8) else { return field.value }
        return string
    }

    private func headerRows(_ headers: [String: String]) -> [DetailRow] {
        headers.isEmpty
            ? [DetailRow(key: "—", value: "no headers")]
            : headers.sorted { $0.key < $1.key }.map { DetailRow(key: $0.key, value: $0.value) }
    }

    // MARK: - Exports (every path carries the same redaction + availability labels)

    public enum ExportFormat: String, CaseIterable, Sendable {
        case curl = "cURL"
        case har = "HAR"
        case csv = "CSV"
        case json = "JSON"
        case text = "Text"
    }

    public func export(_ format: ExportFormat) -> ShareArtifact {
        switch format {
        case .curl: return CurlBuilder.artifact(resolved)
        case .har: return HarBuilder.artifact([resolved])
        case .csv: return CsvWriter.artifact([resolved])
        case .json: return JsonExporter.artifact([resolved])
        case .text: return TextDumpWriter.artifact(resolved)
        }
    }
}
