//
//  PerfAttrs.swift
//  Pantrix
//
//  Performance-event `event_attrs`. `eventType == .performance` covers several event names, each with its
//  own payload; the inspector reads the two that drive charts: `memory_usage` (`PerfAttrs`) and `cpu_usage`
//  (`CpuAttrs`). Mirrored from PantrixCore's `MemoryUsageData` / `CpuUsageData`.
//
//  On iOS only `rss`, `physFootprint` and `interval` are populated in the memory payload; the Java-heap /
//  PSS fields are Android-only and are always absent here (§4i). They stay optional so an Android fixture
//  still decodes, but the memory chart plots `physFootprint` + `rss` and never builds a heap series.
//

import Foundation

/// `memory_usage` event. All sizes in KB; `interval` in ms.
public struct PerfAttrs: Decodable, Equatable, Sendable {
    public let interval: Int64
    public let rss: Int64?            // iOS: Mach resident_size (KB)
    public let physFootprint: Int64?  // iOS: Mach phys_footprint (KB)
    // Android-only — always absent in iOS data:
    public let maxHeap: Int64?
    public let totalHeap: Int64?
    public let freeHeap: Int64?
    public let nativeTotalHeap: Int64?
    public let nativeFreeHeap: Int64?
    public let totalPss: Int?
}

/// `cpu_usage` event. All fields non-optional on both platforms; `percentageUsage` is byte-parity.
public struct CpuAttrs: Decodable, Equatable, Sendable {
    public let numCores: Int
    public let clockSpeed: Int64
    public let startTime: Int64
    public let uptime: Int64
    public let utime: Int64
    public let cutime: Int64
    public let cstime: Int64
    public let stime: Int64
    public let interval: Int64
    public let percentageUsage: Double
}
