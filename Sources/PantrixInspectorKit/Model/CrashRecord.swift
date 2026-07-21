//
//  CrashRecord.swift
//  Pantrix
//
//  The crash payload, mirrored from PantrixCore's `ExceptionEventData` family
//  (`Internal/Processors/Event/Data/Crash/`). In `pntrx.db` these arrive two ways: the crash event's
//  `event_attrs` is a whole `CrashRecord`, while the `pntrx_crashes` table splits `exceptions` and
//  `threads` into their own JSON-array columns (decode those with `[ExceptionUnit]` / `[ExceptionThread]`).
//
//  iOS specifics that shape the UI (§2 of the port plan): a `Frame` carries addresses, not names —
//  `className`/`methodName`/`fileName`/`lineNumber` are filled by server-side symbolication, so a raw
//  on-device frame renders as `moduleName instructionAddress` + an offset from `binaryAddress`.
//  `threadSequence` lives on `ExceptionUnit` (the crashed thread's index), NOT on `ExceptionThread`.
//

import Foundation

public struct CrashRecord: Decodable, Equatable, Sendable {
    public let crashId: String
    public let className: String?
    public let message: String?
    public let exceptions: [ExceptionUnit]
    public let threads: [ExceptionThread]
    public let handled: Bool
    public let foreground: Bool
    public let framework: String
    public let debugImages: [DebugImage]

    enum CodingKeys: String, CodingKey {
        case crashId, className, message, exceptions, threads, handled, foreground, framework, debugImages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        crashId = try c.decode(String.self, forKey: .crashId)
        className = try c.decodeIfPresent(String.self, forKey: .className)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        exceptions = try c.decodeIfPresent([ExceptionUnit].self, forKey: .exceptions) ?? []
        threads = try c.decodeIfPresent([ExceptionThread].self, forKey: .threads) ?? []
        handled = try c.decodeIfPresent(Bool.self, forKey: .handled) ?? false
        foreground = try c.decodeIfPresent(Bool.self, forKey: .foreground) ?? false
        framework = try c.decodeIfPresent(String.self, forKey: .framework) ?? "apple"
        debugImages = try c.decodeIfPresent([DebugImage].self, forKey: .debugImages) ?? []
    }
}

/// An element of the `exceptions` array. `threadSequence` is the crashed thread's index.
public struct ExceptionUnit: Decodable, Equatable, Sendable {
    public let type: String?
    public let message: String?
    public let frames: [Frame]
    public let signal: String?
    public let threadName: String?
    public let threadSequence: Int
    public let osBuildNumber: String?

    enum CodingKeys: String, CodingKey {
        case type, message, frames, signal, threadName, threadSequence, osBuildNumber
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        frames = try c.decodeIfPresent([Frame].self, forKey: .frames) ?? []
        signal = try c.decodeIfPresent(String.self, forKey: .signal)
        threadName = try c.decodeIfPresent(String.self, forKey: .threadName)
        threadSequence = try c.decodeIfPresent(Int.self, forKey: .threadSequence) ?? 0
        osBuildNumber = try c.decodeIfPresent(String.self, forKey: .osBuildNumber)
    }
}

/// An element of the `threads` array — the sibling threads captured at crash time. Only `name` + `frames`.
public struct ExceptionThread: Decodable, Equatable, Sendable {
    public let name: String
    public let frames: [Frame]

    enum CodingKeys: String, CodingKey { case name, frames }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        frames = try c.decodeIfPresent([Frame].self, forKey: .frames) ?? []
    }
}

/// A single stack frame. Addresses are always present on-device; the name fields are symbolication output.
public struct Frame: Decodable, Equatable, Sendable {
    public let className: String?
    public let methodName: String?
    public let fileName: String?
    public let lineNumber: Int?
    public let moduleName: String?
    public let columnNumber: Int?
    public let instructionAddress: String?
    public let binaryAddress: String?
    public let frameIndex: Int?
    public let inApp: Bool

    enum CodingKeys: String, CodingKey {
        case className, methodName, fileName, lineNumber, moduleName, columnNumber
        case instructionAddress, binaryAddress, frameIndex, inApp
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        className = try c.decodeIfPresent(String.self, forKey: .className)
        methodName = try c.decodeIfPresent(String.self, forKey: .methodName)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        lineNumber = try c.decodeIfPresent(Int.self, forKey: .lineNumber)
        moduleName = try c.decodeIfPresent(String.self, forKey: .moduleName)
        columnNumber = try c.decodeIfPresent(Int.self, forKey: .columnNumber)
        instructionAddress = try c.decodeIfPresent(String.self, forKey: .instructionAddress)
        binaryAddress = try c.decodeIfPresent(String.self, forKey: .binaryAddress)
        frameIndex = try c.decodeIfPresent(Int.self, forKey: .frameIndex)
        inApp = try c.decodeIfPresent(Bool.self, forKey: .inApp) ?? false
    }
}

/// A loaded binary image referenced by the crash. `baseAddress` is the load address a frame's
/// `binaryAddress` joins to; `uuid` is the dashless lowercase LC_UUID.
public struct DebugImage: Decodable, Equatable, Sendable {
    public let type: String
    public let uuid: String
    public let baseAddress: String
    public let endAddress: String?
    public let name: String?
    public let path: String?
    public let system: Bool?
    public let arch: String?

    enum CodingKeys: String, CodingKey {
        case type, uuid, baseAddress, endAddress, name, path, system, arch
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "macho"
        uuid = try c.decode(String.self, forKey: .uuid)
        baseAddress = try c.decode(String.self, forKey: .baseAddress)
        endAddress = try c.decodeIfPresent(String.self, forKey: .endAddress)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        system = try c.decodeIfPresent(Bool.self, forKey: .system)
        arch = try c.decodeIfPresent(String.self, forKey: .arch)
    }
}
