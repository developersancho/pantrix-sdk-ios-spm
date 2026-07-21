//
//  HttpStatusText.swift
//  Pantrix
//
//  The reason phrase for an HTTP status code. Ported BYTE-FOR-BYTE from the Android inspector's 18-code
//  table (§7): a fixed table, NOT `HTTPURLResponse.localizedString(forStatusCode:)`, which is locale-
//  dependent and would make a shared HAR's `statusText` change with the device language and break parity.
//  An unknown code returns "" — the same as Android, and the honest answer for a code we don't name.
//

import Foundation

public enum HttpStatusText {
    private static let table: [Int: String] = [
        200: "OK",
        201: "Created",
        204: "No Content",
        301: "Moved Permanently",
        302: "Found",
        304: "Not Modified",
        400: "Bad Request",
        401: "Unauthorized",
        403: "Forbidden",
        404: "Not Found",
        405: "Method Not Allowed",
        408: "Request Timeout",
        422: "Unprocessable Entity",
        429: "Too Many Requests",
        500: "Internal Server Error",
        502: "Bad Gateway",
        503: "Service Unavailable",
        504: "Gateway Timeout",
    ]

    public static func text(for code: Int) -> String {
        table[code] ?? ""
    }
}
