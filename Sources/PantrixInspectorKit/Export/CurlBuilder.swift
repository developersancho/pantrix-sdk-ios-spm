//
//  CurlBuilder.swift
//  Pantrix
//
//  Renders a resolved request as a runnable `curl` command, so QA can replay it off-device. Everything is
//  single-quoted and POSIX-escaped (`'\''`) so a malformed header/body can't break the quoting. Body is
//  capped at 100k chars; GET/HEAD carry no body; a blank method becomes GET. Headers/body are already
//  redacted by the resolver — an absent body is stated as a comment, not silently dropped (§4f).
//

import Foundation

public enum CurlBuilder {
    static let maxBodyChars = 100_000
    static let truncationMarker = "...<truncated>"

    public static func build(_ resolved: ResolvedNetworkRecord) -> String {
        var out = "curl"
        let method = resolved.method
        if method != "GET" { out += " -X \(method)" }
        out += " '\(escape(resolved.record.url))'"

        for (name, value) in resolved.requestHeaders.sorted(by: { $0.key < $1.key }) {
            out += " \\\n  -H '\(escape("\(name): \(value)"))'"
        }

        guard method != "GET", method != "HEAD" else { return out }

        let body = resolved.requestBody
        if body.hasContent {
            let capped = body.value.count > maxBodyChars
                ? String(body.value.prefix(maxBodyChars)) + truncationMarker
                : body.value
            out += " \\\n  --data-raw '\(escape(capped))'"
        } else if !body.note.isEmpty {
            out += " \\\n  # request body: \(body.note)"
        }
        return out
    }

    /// POSIX single-quote escaping: close the quote, emit an escaped quote, reopen (`'\''`).
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    public static func artifact(_ resolved: ResolvedNetworkRecord) -> ShareArtifact {
        ShareArtifact(filename: "request.sh", content: build(resolved), uti: "public.shell-script")
    }
}
