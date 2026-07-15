//
//  PantrixEventMonitor.swift
//  PantrixAlamofire
//
//  Created by developersancho on 15.07.2026.
//

import Foundation
import Alamofire
import PantrixCore

/// Tracks Alamofire traffic with Pantrix — the iOS counterpart of Android's `pantrix-okhttp` /
/// `pantrix-ktor` integration modules. Alamofire owns its own `URLSession`, so `instrumentedSession`
/// doesn't apply; instead this uses Alamofire's first-class observation hook, `EventMonitor`. It reads
/// the parsed response (request, status, timing, and the RESPONSE BODY via `response.data`) and reports
/// it through the public `Pantrix.trackHttp`, tagged `client: "alamofire"`. It never alters the request.
///
/// ```swift
/// let session = Session(eventMonitors: [PantrixEventMonitor()])
/// session.request("https://api.example.com/users").responseDecodable(of: [User].self) { … }
/// ```
public final class PantrixEventMonitor: EventMonitor, @unchecked Sendable {

    /// The `client` value stamped on every event (Android parity: `"okhttp"` / `"ktor"`).
    public static let client = "alamofire"

    public let queue = DispatchQueue(label: "com.pantrix.alamofire-monitor")

    public init() {}

    public func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
        guard let exchange = Self.makeExchange(
            request: response.request,
            response: response.response,
            data: response.data,
            metricsInterval: response.metrics?.taskInterval
        ) else { return }
        exchange.report()
    }
}

/// The Pantrix event derived from an Alamofire response. Extracted as a plain value type built from
/// Foundation types (not `DataResponse`, which can't be constructed in a test), so the whole
/// request→event mapping is unit-testable without a live Alamofire request.
internal struct HttpExchange: Equatable {
    let url: String
    let method: String
    let statusCode: Int?
    let startTime: Int64
    let endTime: Int64
    let requestHeaders: [String: String]?
    let responseHeaders: [String: String]?
    let requestBody: String?
    let requestContentType: String?
    let responseBody: String?
    let responseContentType: String?

    /// Forwards to the public facade with `client = "alamofire"`. The collector owns the gates,
    /// redaction and truncation, exactly like every other HTTP path.
    func report() {
        Pantrix.trackHttp(
            url: url,
            method: method,
            client: PantrixEventMonitor.client,
            statusCode: statusCode,
            startTime: startTime,
            endTime: endTime,
            requestHeaders: requestHeaders,
            responseHeaders: responseHeaders,
            requestBody: requestBody,
            requestContentType: requestContentType,
            responseBody: responseBody,
            responseContentType: responseContentType
        )
    }
}

extension PantrixEventMonitor {
    /// Pure mapping from an Alamofire response's Foundation parts to a `HttpExchange`. Returns nil when
    /// there's no request/response to key on. `now` supplies the fallback timestamp when metrics are
    /// absent (injectable for tests).
    static func makeExchange(
        request: URLRequest?,
        response: HTTPURLResponse?,
        data: Data?,
        metricsInterval: DateInterval?,
        now: () -> Int64 = { Pantrix.getCurrentTime() }
    ) -> HttpExchange? {
        guard let request, let response else { return nil }
        let start = metricsInterval.map { Int64($0.start.timeIntervalSince1970 * 1000) } ?? now()
        let end = metricsInterval.map { Int64($0.end.timeIntervalSince1970 * 1000) } ?? now()
        return HttpExchange(
            url: request.url?.absoluteString ?? "",
            method: request.httpMethod ?? "GET",
            statusCode: response.statusCode,
            startTime: start,
            endTime: end,
            requestHeaders: request.allHTTPHeaderFields,
            responseHeaders: response.allHeaderFields as? [String: String],
            requestBody: request.httpBody.flatMap { String(data: $0, encoding: .utf8) },
            requestContentType: request.value(forHTTPHeaderField: "Content-Type"),
            responseBody: data.flatMap { String(data: $0, encoding: .utf8) },
            responseContentType: response.value(forHTTPHeaderField: "Content-Type")
        )
    }
}
