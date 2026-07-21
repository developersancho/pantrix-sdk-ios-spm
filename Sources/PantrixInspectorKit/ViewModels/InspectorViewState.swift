//
//  InspectorViewState.swift
//  Pantrix
//
//  The loading → error → empty → content state every inspector screen renders through, in priority order.
//  Lives in the Kit so the reduction is tested (the view target's `InspectorStateContainer` just switches
//  on it). The point is that a read ERROR is never shown as an empty screen — a locked device or a renamed
//  column is a distinct, visible state, not "no data".
//

import Foundation

public enum InspectorViewState<Content: Equatable>: Equatable {
    case loading
    case error(String)
    case empty
    case content(Content)

    /// Reduces a fetch result into a state. A thrown error → `.error`; a value the caller deems empty →
    /// `.empty`; otherwise `.content`. `isEmpty` lets the caller decide what "empty" means for its content.
    public static func reduce(_ work: () throws -> Content, isEmpty: (Content) -> Bool) -> InspectorViewState {
        do {
            let value = try work()
            return isEmpty(value) ? .empty : .content(value)
        } catch {
            return .error(describe(error))
        }
    }

    /// A short, user-facing description of a read failure — typed inspector errors get a specific line,
    /// anything else falls back to its localized description.
    public static func describe(_ error: Error) -> String {
        switch error as? InspectorDatabaseError {
        case .databaseNotFound:
            return "Store not found — the SDK hasn't written pntrx.db yet."
        case .openFailed(_, let message):
            return "Couldn't open the store: \(message)"
        case .queryFailed(_, _, let message):
            return "Query failed (schema drift?): \(message)"
        case .none:
            return (error as NSError).localizedDescription
        }
    }

    public var content: Content? {
        if case .content(let value) = self { return value }
        return nil
    }
}
