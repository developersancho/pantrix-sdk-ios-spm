//
//  SystemView.swift
//  Pantrix
//
//  The System tab — Performance / Timeline / Device / Pipeline behind a segmented control. Each sub-view
//  renders its Kit view-model. iOS 15-gated (§4c).
//

import SwiftUI
import PantrixInspectorKit

@available(iOS 15.0, *)
struct SystemView: View {
    let performance: PerformanceViewModel
    let device: DeviceViewModel
    let timeline: TimelineViewModel
    let pipeline: PipelineViewModel

    @State private var segment: Segment = .performance

    private enum Segment: String, CaseIterable { case performance = "Perf", timeline = "Timeline", device = "Device", pipeline = "Pipeline" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.vertical, 8)

            switch segment {
            case .performance: PerformanceView(vm: performance)
            case .timeline: TimelineView(vm: timeline)
            case .device: DeviceView(vm: device)
            case .pipeline: PipelineView(vm: pipeline)
            }
        }
    }
}

// MARK: - Performance

@available(iOS 15.0, *)
private struct PerformanceView: View {
    @ObservedObject var vm: PerformanceViewModel

    var body: some View {
        InspectorStateContainer(state: vm.state, emptyMessage: "No performance samples yet") { snap in
            List {
                Section("CPU") {
                    HStack {
                        ArcGauge(fraction: (snap.cpu.last ?? 0) / 100, color: .orange, centerText: snap.currentCpu)
                        Spacer()
                    }
                    LineChart(values: snap.cpu, scale: snap.cpuScale, color: .orange)
                }
                Section("Memory (\(snap.currentMemory))") {
                    MultiLineChart(series: [
                        .init(values: snap.physFootprint, color: .blue, label: "physFootprint"),
                        .init(values: snap.rss, color: .green, label: "rss"),
                    ], scale: snap.memoryScale)
                }
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

// MARK: - Timeline

@available(iOS 15.0, *)
private struct TimelineView: View {
    @ObservedObject var vm: TimelineViewModel

    var body: some View {
        InspectorStateContainer(state: vm.state, emptyMessage: "No sessions yet") { sessions in
            List {
                ForEach(sessions) { session in
                    Section {
                        ForEach(session.nodes) { node in
                            HStack(spacing: 8) {
                                Circle().fill(InspectorPalette.color(for: node.kind)).frame(width: 8, height: 8)
                                Text(node.name).font(.caption)
                                Spacer()
                                Text(node.clock).font(.caption2).foregroundColor(.secondary).monospacedDigit()
                            }
                        }
                    } header: {
                        HStack {
                            if session.crashed { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.caption2) }
                            Text(session.headerTitle)
                            Spacer()
                            if let duration = session.durationText { Text(duration).foregroundColor(.secondary) }
                        }.font(.caption)
                    }
                }
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

// MARK: - Device

@available(iOS 15.0, *)
private struct DeviceView: View {
    @ObservedObject var vm: DeviceViewModel

    var body: some View {
        InspectorStateContainer(state: vm.state, emptyMessage: "No device info yet") { sections in
            List {
                ForEach(sections) { section in
                    Section(section.title) { ForEach(section.rows) { KeyValueRow(key: $0.key, value: $0.value) } }
                }
                Section {
                    Button {
                        UIPasteboard.general.string = vm.copyAllText
                    } label: {
                        Label("Copy all", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

// MARK: - Pipeline

@available(iOS 15.0, *)
private struct PipelineView: View {
    @ObservedObject var vm: PipelineViewModel

    var body: some View {
        InspectorStateContainer(state: vm.state, emptyMessage: "Nothing pending — the pipeline is clear") { snap in
            List {
                Section("Last app exit") { LaunchReadoutRows(launch: snap.launch) }
                Section("Batches (\(snap.batches.count))") {
                    if snap.batches.isEmpty {
                        Text("No pending batches").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(snap.batches) { batch in
                            HStack {
                                Text(batch.batchId.prefix(12) + "…").font(.system(.caption, design: .monospaced))
                                Spacer()
                                Text("\(batch.eventCount) events").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                if !snap.appExits.isEmpty {
                    Section("Pending app-exit pairings") {
                        ForEach(snap.appExits, id: \.pid) { exit in
                            KeyValueRow(key: "session \(exit.sessionId.prefix(8))", value: "pid \(exit.pid)")
                        }
                    }
                }
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

@available(iOS 15.0, *)
private struct LaunchReadoutRows: View {
    let launch: LaunchDisplay

    var body: some View {
        if !launch.present {
            Text("No app-exit recorded").foregroundColor(.secondary).font(.caption)
        } else {
            if launch.stale {
                Text("⚠︎ From an earlier launch (not this run)").font(.caption2).foregroundColor(.orange)
            }
            ForEach(launch.rows) { KeyValueRow(key: $0.key, value: $0.value) }
        }
    }
}
