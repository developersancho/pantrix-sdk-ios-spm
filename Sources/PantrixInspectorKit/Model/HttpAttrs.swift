//
//  HttpAttrs.swift
//  Pantrix
//
//  The `event_attrs` payload of an HTTP `network` event — PantrixCore's `NetworkEventData`. This is the
//  ONE stored struct with a `CodingKeys` override: the Swift property `networkProtocol` is stored under the
//  wire key `"protocol"` (a Swift keyword can't be a bare property name). Every other field keys under its
//  own name. Bodies/headers are present only when the host opted into `trackHttpBody`/`trackHttpHeaders`
//  AND the traffic went through a delegate-based `URLSession` — otherwise they are absent (see §4f).
//

import Foundation

public struct HttpAttrs: Decodable, Equatable, Sendable {
    public let client: String
    public let url: String
    public let method: String
    public let statusCode: Int?
    public let path: String?
    public let startTime: Int64
    public let endTime: Int64
    public let duration: Int64
    public let failureReason: String?
    public let failureDescription: String?
    public let requestHeaders: [String: String]?
    public let responseHeaders: [String: String]?
    public let requestBody: String?
    public let responseBody: String?
    public let proxies: String?
    public let domainName: String?
    public let dnsAddress: String?
    public let networkProtocol: String?

    enum CodingKeys: String, CodingKey {
        case client, url, method, statusCode, path, startTime, endTime, duration
        case failureReason, failureDescription, requestHeaders, responseHeaders
        case requestBody, responseBody, proxies, domainName, dnsAddress
        case networkProtocol = "protocol"
    }
}
