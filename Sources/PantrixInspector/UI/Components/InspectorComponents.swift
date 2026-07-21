//
//  InspectorComponents.swift
//  Pantrix
//
//  Small shared views: the loading/error/empty/content container, a key–value row, and a status pill.
//  All iOS 15-gated (§4c). These render Kit view-state/values; they hold no data logic.
//

import SwiftUI
import PantrixInspectorKit

/// Switches on a Kit `InspectorViewState` in priority order: loading → error → empty → content. An error is
/// its own visible state, never a blank screen.
@available(iOS 15.0, *)
struct InspectorStateContainer<Content: Equatable, Body: View>: View {
    let state: InspectorViewState<Content>
    let emptyMessage: String
    @ViewBuilder let content: (Content) -> Body

    var body: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            InspectorMessageView(symbol: "exclamationmark.triangle.fill", tint: .red, title: "Couldn't read the store", detail: message)
        case .empty:
            InspectorMessageView(symbol: "tray", tint: .secondary, title: emptyMessage, detail: nil)
        case .content(let value):
            content(value)
        }
    }
}

@available(iOS 15.0, *)
struct InspectorMessageView: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.largeTitle).foregroundColor(tint)
            Text(title).font(.headline).multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A monospaced key–value row for the detail screen; tap to copy the value.
@available(iOS 15.0, *)
struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(key).font(.caption).foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

/// A small tinted capsule label (e.g. an event kind).
@available(iOS 15.0, *)
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundColor(color)
    }
}
