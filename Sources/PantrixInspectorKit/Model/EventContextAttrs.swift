//
//  EventContextAttrs.swift
//  Pantrix
//
//  The seven per-event context blobs the SDK stores in the `*_attrs` columns, as Decodables. The SDK
//  serializes them with a bare `JSONEncoder` (`.sortedKeys`, NO key strategy) and omits nil optionals
//  (`encodeIfPresent`), so: JSON keys equal the Swift property names verbatim, and every optional here is a
//  field that may simply be absent. Field names are lifted 1:1 from PantrixCore's `Event*Data`
//  (`Internal/Processors/Event/Data/EventData.swift`) — do not rename them, they ARE the wire schema.
//
//  None of these need `CodingKeys`; the only column struct that overrides a key is the HTTP payload
//  (`networkProtocol` → `"protocol"`), which lives in HttpAttrs.swift.
//

import Foundation

/// `session_attrs` — `EventSessionData`.
public struct SessionAttrs: Decodable, Equatable, Sendable {
    public let sessionId: String
    public let pid: Int
    public let buildId: String
    public let startDate: String
    public let endDate: String?
    public let duration: Int64?
    public let crashed: Bool
    public let supportsAppExit: Bool
}

/// `device_attrs` — `EventDeviceData`. `model` is the model code; `osSdk` is a String on the wire.
public struct DeviceAttrs: Decodable, Equatable, Sendable {
    public let installId: String
    public let cdId: String?
    public let deviceId: String
    public let brand: String
    public let model: String
    public let manufacturer: String
    public let orientation: String
    public let isPhysical: Bool
    public let isRooted: Bool
    public let isFoldable: Bool
    public let hasNfc: Bool
    public let carrier: String
    public let osName: String
    public let osVersion: String
    public let osSdk: String
    public let languageCode: String
    public let countryCode: String
    public let timeZone: String
    public let locale: String
    public let density: Float
    public let densityDpi: Int
    public let widthPx: Int
    public let heightPx: Int
}

/// `build_attrs` — `EventBuildData`. `versionCode` is a String on the wire.
public struct BuildAttrs: Decodable, Equatable, Sendable {
    public let buildId: String
    public let appId: String
    public let appName: String
    public let versionCode: String
    public let versionName: String
    public let isDebuggable: Bool
}

/// `network_attrs` — `EventNetworkData`, the connectivity CONTEXT on every event (not the HTTP payload).
/// The property is literally named `connectionType`; no key override.
public struct NetworkContextAttrs: Decodable, Equatable, Sendable {
    public let connectionType: String
    public let carrierId: String?
    public let carrierName: String?
    public let upKbps: Int64?
    public let downKbps: Int64?
    public let strength: Int64?
}

/// `screen_attrs` — `EventScreenData`. Note the wire key is `durationTime`, not `duration`.
public struct ScreenAttrs: Decodable, Equatable, Sendable {
    public let screenId: String
    public let screenName: String
    public let className: String
    public let category: String
    public let enteredAt: String?
    public let loadTime: Int64?
    public let durationTime: Int64?
}

/// `user_attrs` — `EventUserData`. `userProperties` is a free-form scalar map.
public struct UserAttrs: Decodable, Equatable, Sendable {
    public let userId: String?
    public let userProperties: [String: InspectorJSONValue]?
}

/// `power_state_attrs` — `EventPowerStateData`. iOS emits only these two; `thermalThrottlingEnabled` is
/// true only under `.serious`/`.critical` thermal state.
public struct PowerStateAttrs: Decodable, Equatable, Sendable {
    public let lowPowerModeEnabled: Bool?
    public let thermalThrottlingEnabled: Bool
}

/// A decoded JSON scalar/container, for free-form maps like `userProperties` where the SDK stores mixed
/// scalar types. Kept minimal — enough to display any value the SDK could have written.
public enum InspectorJSONValue: Decodable, Equatable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case null
    case array([InspectorJSONValue])
    case object([String: InspectorJSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int64.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([InspectorJSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: InspectorJSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
        }
    }

    /// A flat display string for a leaf value; containers render their JSON-ish shape.
    public var displayString: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let a): return "[" + a.map(\.displayString).joined(separator: ", ") + "]"
        case .object(let o):
            return "{" + o.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.displayString)" }.joined(separator: ", ") + "}"
        }
    }
}
