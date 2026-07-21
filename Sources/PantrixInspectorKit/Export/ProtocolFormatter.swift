//
//  ProtocolFormatter.swift
//  Pantrix
//
//  Turns the raw negotiated-protocol wire value (`HttpAttrs.protocol` / `pntrx_network.protocol`) into a
//  display / HAR `httpVersion` string, from ONE place — both the detail badge and `HarBuilder` use it, so
//  they can't disagree. iOS `URLSession` reports values like `h2`, `h3`, `http/1.1`; a value we don't map
//  is upper-cased as-is rather than guessed. Empty → `HTTP/1.1` (HAR requires a version).
//

import Foundation

public enum ProtocolFormatter {
    public static func httpVersion(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return "HTTP/1.1" }
        switch value.lowercased() {
        case "h2", "http/2", "http/2.0": return "HTTP/2"
        case "h3", "http/3", "http/3.0": return "HTTP/3"
        case "http/1.1": return "HTTP/1.1"
        case "http/1.0": return "HTTP/1.0"
        case "spdy/3.1": return "SPDY/3.1"
        default:
            // Mirror the Android transform for `HTTP_x_y` style values; otherwise upper-case verbatim.
            let up = value.uppercased()
            if up.hasPrefix("HTTP_") {
                return "HTTP/" + up.dropFirst("HTTP_".count).replacingOccurrences(of: "_", with: ".")
            }
            return up
        }
    }
}
