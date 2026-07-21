//
//  DashboardStatsHeader.swift
//  Pantrix
//
//  The Events tab's header — total / reported counts + a per-kind breakdown. It is a HEADER, not a separate
//  Dashboard screen (§7): the Android hub-and-spoke dashboard is replaced by iOS's TabView, and its summary
//  lives here. Renders the view-model's `InspectorEventStats`; iOS 15-gated (§4c).
//

import SwiftUI
import PantrixInspectorKit

@available(iOS 15.0, *)
struct DashboardStatsHeader: View {
    let stats: InspectorEventStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                metric("\(stats.total)", "events")
                metric("\(stats.reported)", "reported")
                metric("\(stats.typeCount)", "types")
            }
            if !stats.chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(stats.chips) { chip in
                            StatusPill(text: "\(chip.kind.wireValue) \(chip.count)",
                                       color: InspectorPalette.color(for: chip.kind))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}
