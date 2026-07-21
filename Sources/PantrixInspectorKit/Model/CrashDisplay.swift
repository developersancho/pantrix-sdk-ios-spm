//
//  CrashDisplay.swift
//  Pantrix
//
//  Crash classification + stack-frame rendering. THE critical iOS difference (§2 of the port plan): an
//  on-device `Frame` carries ADDRESSES, not names — `className`/`methodName`/`fileName`/`lineNumber` are
//  filled by server-side symbolication. So an unsymbolicated frame must render as
//  `moduleName 0xinstructionAddress + offset` (offset = instructionAddress − binaryAddress), NOT as
//  `className.methodName` — porting Android's name logic verbatim would leave every line blank.
//

import Foundation

/// How a crash record is classified for the list + filter chips.
public enum CrashKind: String, CaseIterable, Sendable {
    case fatal
    case handled
    case anr

    public var label: String {
        switch self {
        case .fatal: return "Fatal"
        case .handled: return "Handled"
        case .anr: return "ANR"
        }
    }

    /// ANR events go through `trackCrash` with `event_name == "anr"`; everything else splits on `handled`.
    public static func of(_ row: CrashRow) -> CrashKind {
        if row.eventName == "anr" { return .anr }
        return row.handled ? .handled : .fatal
    }
}

public enum FrameFormatter {
    /// Parses a `0x…` (or bare) hex address to a value.
    public static func hexValue(_ string: String?) -> UInt64? {
        guard let string, !string.isEmpty else { return nil }
        let cleaned = (string.hasPrefix("0x") || string.hasPrefix("0X")) ? String(string.dropFirst(2)) : string
        return UInt64(cleaned, radix: 16)
    }

    /// The frame's offset into its binary image (`instructionAddress − binaryAddress`), or `nil` if either
    /// address is missing/unparseable.
    public static func offset(_ frame: Frame) -> Int64? {
        guard let instruction = hexValue(frame.instructionAddress), let base = hexValue(frame.binaryAddress) else { return nil }
        return Int64(bitPattern: instruction &- base)
    }

    /// Whether server-side symbolication has filled a name for this frame.
    public static func isSymbolicated(_ frame: Frame) -> Bool {
        (frame.methodName?.isEmpty == false) || (frame.className?.isEmpty == false)
    }

    /// A single rendered stack line: a symbol when symbolicated, otherwise `module 0xaddr + offset`.
    public static func line(_ frame: Frame) -> String {
        let module = frame.moduleName.flatMap { $0.isEmpty ? nil : $0 } ?? "?"
        if isSymbolicated(frame) {
            var symbol = [frame.className, frame.methodName].compactMap { $0.flatMap { $0.isEmpty ? nil : $0 } }.joined(separator: ".")
            if symbol.isEmpty { symbol = "?" }
            if let file = frame.fileName, !file.isEmpty, let lineNo = frame.lineNumber {
                return "\(module) \(symbol) (\(file):\(lineNo))"
            }
            return "\(module) \(symbol)"
        }
        let address = frame.instructionAddress ?? "0x0"
        if let offset = offset(frame) {
            return "\(module) \(address) + \(offset)"
        }
        return "\(module) \(address)"
    }

    /// The blame line — the first in-app frame if there is one, else the first frame — for a list preview.
    public static func blameLine(_ frames: [Frame]) -> String? {
        guard !frames.isEmpty else { return nil }
        let frame = frames.first(where: { $0.inApp }) ?? frames[0]
        return line(frame)
    }
}
