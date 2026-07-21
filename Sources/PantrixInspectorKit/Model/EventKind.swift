//
//  EventKind.swift
//  Pantrix
//
//  The `event_type` wire values, mirrored from PantrixCore's `EventType`. Deliberately carries NO colour
//  or icon — unlike Android's `EventType`, which folds Compose `Color` into the data layer. On iOS that
//  mapping is the view target's job (`InspectorPalette` / `SFSymbolMap`), so the Kit stays UI-free and the
//  layer rule (§4h) holds. An unrecognised value round-trips through `.other(_)` rather than being dropped,
//  so a new SDK event type shows up in the inspector instead of vanishing.
//

import Foundation

public enum EventKind: Equatable, Hashable, Sendable {
    case custom
    case interaction
    case screen
    case network
    case networkChange
    case performance
    case lifecycle
    case appLaunch
    case crash
    case session
    /// A wire value this build doesn't know — forward-compatible, still displayable/filterable by its raw.
    case other(String)

    public init(wireValue: String) {
        switch wireValue {
        case "custom": self = .custom
        case "interaction": self = .interaction
        case "screen": self = .screen
        case "network": self = .network
        case "network_change": self = .networkChange
        case "performance": self = .performance
        case "lifecycle": self = .lifecycle
        case "app_launch": self = .appLaunch
        case "crash": self = .crash
        case "session": self = .session
        default: self = .other(wireValue)
        }
    }

    public var wireValue: String {
        switch self {
        case .custom: return "custom"
        case .interaction: return "interaction"
        case .screen: return "screen"
        case .network: return "network"
        case .networkChange: return "network_change"
        case .performance: return "performance"
        case .lifecycle: return "lifecycle"
        case .appLaunch: return "app_launch"
        case .crash: return "crash"
        case .session: return "session"
        case .other(let raw): return raw
        }
    }

    /// The ten types the SDK ships today, for filter chips. `.other` is intentionally excluded — it is a
    /// catch-all, not a selectable type.
    public static let known: [EventKind] = [
        .custom, .interaction, .screen, .network, .networkChange,
        .performance, .lifecycle, .appLaunch, .crash, .session,
    ]
}
