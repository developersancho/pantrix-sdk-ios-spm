//
//  InspectorPaths.swift
//  Pantrix
//
//  Resolves the on-disk location of the SDK's store WITHOUT importing PantrixCore. PantrixCore writes
//  `pntrx.db` to `Library/Application Support/` (via `FileManager.applicationSupportDirectory`); the
//  inspector runs in the same process, so the same lookup yields the same file. Kept separate from
//  `InspectorDatabase` so the (host-dependent) path resolution and the (pure) SQLite access are testable
//  in isolation — a test points `InspectorDatabase` at any URL it likes.
//

import Foundation

internal enum InspectorPaths {
    /// The SDK database URL, or `nil` if Application Support can't be resolved (never seen on iOS, where
    /// the directory is always available for the app container). Does NOT check that the file exists —
    /// that is `InspectorDatabase`'s job, so "no Application Support" and "SDK hasn't run yet" stay
    /// distinct failures.
    static func databaseURL(fileManager: FileManager = .default) -> URL? {
        guard let support = try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return nil }
        return support.appendingPathComponent(InspectorSchema.databaseName)
    }
}
