//
//  Aggregations.swift
//  Pantrix
//
//  Pure reductions over already-fetched rows — the numbers the Events-tab stats header (Phase 2) and the
//  Performance charts (Phase 5) need. Kept out of the view target (§4h): the view renders these, it doesn't
//  compute them.
//

import Foundation

public enum Aggregations {

    // MARK: - Event stats (Phase 2 header)

    public struct EventStats: Equatable, Sendable {
        public let total: Int
        public let reported: Int
        public let byKind: [EventKind: Int]
        /// Kinds present, ordered by descending count then wire value — a stable order for chips.
        public let kindsByFrequency: [(kind: EventKind, count: Int)]

        public static func == (lhs: EventStats, rhs: EventStats) -> Bool {
            lhs.total == rhs.total && lhs.reported == rhs.reported && lhs.byKind == rhs.byKind
        }
    }

    public static func eventStats(_ events: [InspectorEvent]) -> EventStats {
        var byKind: [EventKind: Int] = [:]
        var reported = 0
        for e in events {
            byKind[e.kind, default: 0] += 1
            if e.isReported { reported += 1 }
        }
        let ranked = byKind
            .sorted {
                $0.value != $1.value
                    ? $0.value > $1.value                       // higher count first
                    : $0.key.wireValue > $1.key.wireValue       // tie-break: wire value descending, stable
            }
            .map { (kind: $0.key, count: $0.value) }
        return EventStats(total: events.count, reported: reported, byKind: byKind, kindsByFrequency: ranked)
    }

    // MARK: - Performance series (Phase 5 charts)

    public struct MemorySample: Equatable, Sendable {
        public let epochMillis: Int64
        public let rss: Int64?
        public let physFootprint: Int64?
    }

    public struct CpuSample: Equatable, Sendable {
        public let epochMillis: Int64
        public let percentageUsage: Double
    }

    /// Memory samples in chronological order, from `memory_usage` events. Rows that don't decode or lack a
    /// parseable date are skipped (a corrupt sample shouldn't blank the whole chart). iOS fills only
    /// `rss`/`physFootprint`; a heap series is never built.
    public static func memorySeries(_ events: [InspectorEvent]) -> [MemorySample] {
        events.compactMap { event in
            guard event.name == "memory_usage",
                  let attrs = try? event.memory(),
                  let ms = InspectorFormatters.epochMillis(fromISO: event.date) else { return nil }
            return MemorySample(epochMillis: ms, rss: attrs.rss, physFootprint: attrs.physFootprint)
        }.sorted { $0.epochMillis < $1.epochMillis }
    }

    /// CPU samples in chronological order, from `cpu_usage` events.
    public static func cpuSeries(_ events: [InspectorEvent]) -> [CpuSample] {
        events.compactMap { event in
            guard event.name == "cpu_usage",
                  let attrs = try? event.cpu(),
                  let ms = InspectorFormatters.epochMillis(fromISO: event.date) else { return nil }
            return CpuSample(epochMillis: ms, percentageUsage: attrs.percentageUsage)
        }.sorted { $0.epochMillis < $1.epochMillis }
    }

    /// The CURRENT (most recent) sample — the one with the greatest timestamp. NOT `lastOrNull()` over an
    /// unsorted list: the series is sorted ascending, so `.last` is genuinely newest. This is the fix for
    /// Android's bug where "current" read the reversed list's tail and showed the oldest sample.
    public static func currentMemory(_ series: [MemorySample]) -> MemorySample? { series.last }
    public static func currentCpu(_ series: [CpuSample]) -> CpuSample? { series.last }
}
