//
//  PerformanceViewModel.swift
//  Pantrix
//
//  Builds the memory + CPU chart series and the "current" readouts from `memory_usage` / `cpu_usage`
//  events. iOS fills only `physFootprint` + `rss` for memory (§4i) — no heap/PSS series is ever built.
//  "Current" is the NEWEST sample (`Aggregations.currentMemory/Cpu`), fixing Android's reversed-list bug.
//

import Foundation
import Combine

public struct PerformanceSnapshot: Equatable, Sendable {
    public let physFootprint: [Double]   // KB, chronological
    public let rss: [Double]
    public let memoryScale: ChartScale
    public let cpu: [Double]             // percentage
    public let cpuScale: ChartScale
    public let currentMemory: String     // formatted, or "—"
    public let currentCpu: String
    public let sampleCount: Int

    public static let empty = PerformanceSnapshot(
        physFootprint: [], rss: [], memoryScale: ChartScale(values: []),
        cpu: [], cpuScale: ChartScale(values: []), currentMemory: "—", currentCpu: "—", sampleCount: 0)
}

@MainActor
public final class PerformanceViewModel: ObservableObject {
    @Published public private(set) var state: InspectorViewState<PerformanceSnapshot> = .loading

    private let store: InspectorStore
    private let pageSize: Int
    private var subscription: UUID?
    private var hasLoadedOnce = false

    public init(store: InspectorStore, pageSize: Int = 500) {
        self.store = store
        self.pageSize = pageSize
    }

    public func start() {
        subscription = store.subscribe { [weak self] in self?.reload() }
        reload()
    }

    public func stop() {
        if let subscription { store.unsubscribe(subscription) }
        subscription = nil
    }

    public func reload() {
        if !hasLoadedOnce { state = .loading }
        do {
            let events = try store.repo.events(filter: EventFilter(types: [.performance]), pageSize: pageSize)
            hasLoadedOnce = true
            let snapshot = Self.snapshot(from: events)
            state = snapshot.sampleCount == 0 ? .empty : .content(snapshot)
        } catch {
            state = .error(InspectorViewState<PerformanceSnapshot>.describe(error))
        }
    }

    static func snapshot(from events: [InspectorEvent]) -> PerformanceSnapshot {
        let memory = Aggregations.memorySeries(events)
        let cpu = Aggregations.cpuSeries(events)

        let phys = memory.compactMap { $0.physFootprint.map(Double.init) }
        let rss = memory.compactMap { $0.rss.map(Double.init) }
        let cpuValues = cpu.map(\.percentageUsage)

        let currentMemory = Aggregations.currentMemory(memory).map { sample -> String in
            let physText = sample.physFootprint.map { InspectorFormatters.size(kilobytes: $0) } ?? "—"
            let rssText = sample.rss.map { InspectorFormatters.size(kilobytes: $0) } ?? "—"
            return "phys \(physText) · rss \(rssText)"
        } ?? "—"
        let currentCpu = Aggregations.currentCpu(cpu).map { String(format: "%.1f%%", $0.percentageUsage) } ?? "—"

        return PerformanceSnapshot(
            physFootprint: phys,
            rss: rss,
            memoryScale: ChartScale(values: phys + rss),
            cpu: cpuValues,
            cpuScale: ChartScale(min: 0, max: Swift.max(100, cpuValues.max() ?? 0)),
            currentMemory: currentMemory,
            currentCpu: currentCpu,
            sampleCount: memory.count + cpu.count)
    }
}
