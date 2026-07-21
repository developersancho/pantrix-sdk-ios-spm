//
//  InspectorPalette.swift
//  Pantrix
//
//  Colour + icon mapping per event kind. This is the view target's job — the Kit's `EventKind` deliberately
//  carries no colour (unlike Android's `EventType`), so the data layer stays UI-free and the §4h layer rule
//  holds. All types here are iOS 15-gated per §4c.
//

import SwiftUI
import PantrixInspectorKit

@available(iOS 15.0, *)
enum InspectorPalette {
    static func color(for kind: EventKind) -> Color {
        switch kind {
        case .crash: return .red
        case .performance: return .orange
        case .network: return .blue
        case .networkChange: return .teal
        case .screen: return .purple
        case .session: return .green
        case .lifecycle: return .mint
        case .appLaunch: return .indigo
        case .interaction: return .pink
        case .custom: return .gray
        case .other: return .secondary
        }
    }
}

@available(iOS 15.0, *)
enum SFSymbolMap {
    static func symbol(for kind: EventKind) -> String {
        switch kind {
        case .crash: return "exclamationmark.triangle.fill"
        case .performance: return "gauge.medium"
        case .network: return "network"
        case .networkChange: return "wifi"
        case .screen: return "rectangle.on.rectangle"
        case .session: return "clock"
        case .lifecycle: return "arrow.triangle.2.circlepath"
        case .appLaunch: return "bolt.fill"
        case .interaction: return "hand.tap"
        case .custom: return "circle.fill"
        case .other: return "questionmark.circle"
        }
    }
}
