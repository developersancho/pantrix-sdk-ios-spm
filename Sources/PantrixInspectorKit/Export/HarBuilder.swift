//
//  HarBuilder.swift
//  Pantrix
//
//  Builds an HTTP Archive (HAR 1.2) document from resolved requests, so a transaction (or the whole list)
//  drops into any HAR-aware tool. Codable + `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`.
//  Headers/bodies are already redacted; an absent body carries its availability note in a `comment` field
//  rather than a fake empty string. Fields we don't capture (cookies, detailed timings, TLS) are omitted or
//  sent as -1 per the spec. Ported from the Android inspector — which shipped NO HarBuilder test.
//

import Foundation

public enum HarBuilder {

    public static func build(_ records: [ResolvedNetworkRecord]) -> String {
        let har = Har(log: Log(
            creator: Creator(),
            entries: records.map(entry)
        ))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(har), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    public static func artifact(_ records: [ResolvedNetworkRecord]) -> ShareArtifact {
        ShareArtifact(filename: "pantrix-network.har", content: build(records), uti: "public.json")
    }

    private static func entry(_ r: ResolvedNetworkRecord) -> Entry {
        let version = r.httpVersion
        let request = Request(
            method: r.method,
            url: r.record.url,
            httpVersion: version,
            headers: harHeaders(r.requestHeaders),
            headersSize: -1,
            bodySize: -1,
            postData: postData(r.requestBody, contentType: contentType(r.requestHeaders))
        )
        let response = Response(
            status: Int(r.record.statusCode),
            statusText: r.statusText,
            httpVersion: version,
            headers: harHeaders(r.responseHeaders),
            content: Content(
                size: -1,
                mimeType: contentType(r.responseHeaders),
                text: r.responseBody.hasContent ? r.responseBody.value : "",
                comment: r.responseBody.note.isEmpty ? nil : r.responseBody.note
            ),
            redirectURL: "",
            headersSize: -1,
            bodySize: -1
        )
        return Entry(
            startedDateTime: r.record.eventDate,
            time: r.record.duration,
            request: request,
            response: response,
            cache: Cache(),
            timings: Timings(send: 0, wait: r.record.duration, receive: 0)
        )
    }

    private static func harHeaders(_ map: [String: String]) -> [Header] {
        map.sorted { $0.key < $1.key }.map { Header(name: $0.key, value: $0.value) }
    }

    private static func postData(_ body: NetworkExportField, contentType: String) -> PostData? {
        guard body.hasContent || !body.note.isEmpty else { return nil }
        return PostData(
            mimeType: contentType,
            text: body.hasContent ? body.value : "",
            comment: body.note.isEmpty ? nil : body.note
        )
    }

    private static func contentType(_ headers: [String: String]) -> String {
        headers.first { $0.key.lowercased() == "content-type" }?.value ?? ""
    }

    // MARK: - HAR 1.2 model

    private struct Har: Encodable { let log: Log }
    private struct Log: Encodable { let version = "1.2"; let creator: Creator; let entries: [Entry] }
    private struct Creator: Encodable { let name = "Pantrix Inspector"; let version = "1.0" }
    private struct Entry: Encodable {
        let startedDateTime: String
        let time: Int64
        let request: Request
        let response: Response
        let cache: Cache
        let timings: Timings
    }
    private struct Request: Encodable {
        let method: String
        let url: String
        let httpVersion: String
        let headers: [Header]
        let queryString: [Header] = []
        let headersSize: Int
        let bodySize: Int
        let postData: PostData?
    }
    private struct Response: Encodable {
        let status: Int
        let statusText: String
        let httpVersion: String
        let headers: [Header]
        let content: Content
        let redirectURL: String
        let headersSize: Int
        let bodySize: Int
    }
    private struct Header: Encodable { let name: String; let value: String }
    private struct PostData: Encodable { let mimeType: String; let text: String; let comment: String? }
    private struct Content: Encodable { let size: Int; let mimeType: String; let text: String; let comment: String? }
    private struct Cache: Encodable {}
    private struct Timings: Encodable { let send: Int; let wait: Int64; let receive: Int }
}
