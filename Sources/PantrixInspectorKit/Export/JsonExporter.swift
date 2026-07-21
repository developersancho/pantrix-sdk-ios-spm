//
//  JsonExporter.swift
//  Pantrix
//
//  Exports resolved requests as a proper NESTED JSON array — headers as real objects, bodies as strings,
//  each body carrying its availability. Unlike the Android inspector, which double-encoded `event_attrs`
//  (a JSON string inside a JSON string), this nests cleanly. Redaction is already applied by the resolver.
//

import Foundation

public enum JsonExporter {

    public static func build(_ records: [ResolvedNetworkRecord]) -> String {
        let items = records.map(item)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(items), let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    public static func artifact(_ records: [ResolvedNetworkRecord]) -> ShareArtifact {
        ShareArtifact(filename: "pantrix-network.json", content: build(records), uti: "public.json")
    }

    private static func item(_ r: ResolvedNetworkRecord) -> Item {
        Item(
            date: r.record.eventDate,
            method: r.method,
            url: r.record.url,
            status: Int(r.record.statusCode),
            statusText: r.statusText,
            durationMs: r.record.duration,
            httpVersion: r.httpVersion,
            requestHeaders: r.requestHeaders,
            responseHeaders: r.responseHeaders,
            requestBody: Body(r.requestBody),
            responseBody: Body(r.responseBody)
        )
    }

    private struct Item: Encodable {
        let date: String
        let method: String
        let url: String
        let status: Int
        let statusText: String
        let durationMs: Int64
        let httpVersion: String
        let requestHeaders: [String: String]
        let responseHeaders: [String: String]
        let requestBody: Body
        let responseBody: Body
    }

    private struct Body: Encodable {
        let content: String?
        let availability: String
        init(_ field: NetworkExportField) {
            self.content = field.hasContent ? field.value : nil
            self.availability = field.hasContent ? "captured" : field.note
        }
    }
}
