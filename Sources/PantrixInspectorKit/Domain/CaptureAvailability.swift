//
//  CaptureAvailability.swift
//  Pantrix
//
//  Why a network field is empty (§4f of the port plan). The `pntrx_network` columns are `TEXT NOT NULL`,
//  so a missing body/header arrives as an empty STRING, and the row alone can't tell "capture was off" from
//  "the body was genuinely empty" from "iOS structurally can't capture this". The honest answer needs the
//  host's capture config, which the classifier takes as input. Every UI field and every export path carries
//  this label so a blank value is never mistaken for "the request had no body".
//

import Foundation

public enum CaptureAvailability: Equatable, Sendable {
    /// A real captured value is present.
    case captured
    /// The host didn't enable capture for this field (`trackHttpBody` / `trackHttpHeaders` off).
    case captureDisabled
    /// iOS can't capture this on the path the request took (e.g. a streamed request body, or a
    /// completion-handler/`async` response body Apple never hands to a delegate).
    case notCapturableOnIOS(reason: String)
    /// Captured, but cut at `limit` bytes.
    case truncated(limit: Int)
    /// Present but withheld by redaction.
    case redacted
    /// Capture was on and the value really was empty.
    case genuinelyEmpty

    /// Classifies a captured field from its stored value + whether the host enabled capture for it. The
    /// structural iOS limits (`.notCapturableOnIOS`) and `.redacted` are decided by the caller, which knows
    /// the request's task type and the redaction outcome — they are passed via `structuralReason` /
    /// `wasRedacted`, checked before the value.
    public static func classify(
        value: String,
        captureEnabled: Bool,
        structuralReason: String? = nil,
        wasRedacted: Bool = false,
        truncationLimit: Int? = nil
    ) -> CaptureAvailability {
        if wasRedacted { return .redacted }
        if let structuralReason { return .notCapturableOnIOS(reason: structuralReason) }
        if !captureEnabled { return .captureDisabled }
        if value.isEmpty { return .genuinelyEmpty }
        if let limit = truncationLimit, value.utf8.count >= limit { return .truncated(limit: limit) }
        return .captured
    }

    /// True when the field holds a real, showable value.
    public var hasContent: Bool {
        switch self {
        case .captured, .truncated: return true
        case .captureDisabled, .notCapturableOnIOS, .redacted, .genuinelyEmpty: return false
        }
    }
}
