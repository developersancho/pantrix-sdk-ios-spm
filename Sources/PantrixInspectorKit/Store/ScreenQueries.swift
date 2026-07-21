//
//  ScreenQueries.swift
//  Pantrix
//
//  Reads `pntrx_screens` — resolves a `screen_id` (which events and sessions carry) to a human screen name.
//  Small table; read whole and indexed by id in the repository.
//

import Foundation

enum ScreenQueries {
    static let all: String = {
        typealias S = InspectorSchema.Screens
        return "SELECT \(S.screenId), \(S.screenName), \(S.className), \(S.category) FROM \(S.table)"
    }()

    static func map(_ row: SQLiteRow) -> ScreenRow {
        typealias S = InspectorSchema.Screens
        return ScreenRow(
            screenId: row.requiredString(S.screenId),
            screenName: row.requiredString(S.screenName),
            className: row.requiredString(S.className),
            category: row.requiredString(S.category)
        )
    }
}
