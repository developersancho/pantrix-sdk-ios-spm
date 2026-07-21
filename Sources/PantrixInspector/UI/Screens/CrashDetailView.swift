//
//  CrashDetailView.swift
//  Pantrix
//
//  One crash across 4 segments: Overview / Stack Trace / Threads / Raw. Stack frames render as address +
//  offset when unsymbolicated (never blank); in-app frames are emphasised. The crashed thread is flagged.
//  iOS 15-gated (§4c).
//

import SwiftUI
import PantrixInspectorKit

@available(iOS 15.0, *)
struct CrashDetailView: View {
    @StateObject private var vm: CrashDetailViewModel
    @State private var segment: Segment = .overview

    init(vm: CrashDetailViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }

    private enum Segment: String, CaseIterable { case overview = "Overview", stack = "Stack", threads = "Threads", raw = "Raw" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.vertical, 8)
            content
        }
        .navigationTitle(vm.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .overview:
            List { ForEach(vm.overviewRows) { KeyValueRow(key: $0.key, value: $0.value) } }
        case .stack:
            List {
                if vm.stackTrace.isEmpty {
                    Text("No frames").foregroundColor(.secondary)
                } else {
                    ForEach(vm.stackTrace) { FrameRow(index: $0.index, text: $0.text, inApp: $0.inApp) }
                }
            }
            .listStyle(.plain)
        case .threads:
            List {
                ForEach(vm.threadList) { thread in
                    Section {
                        ForEach(thread.frames) { FrameRow(index: $0.index, text: $0.text, inApp: $0.inApp) }
                    } header: {
                        HStack {
                            Text(thread.name)
                            if thread.isCrashed { StatusPill(text: "crashed", color: .red) }
                        }
                    }
                }
            }
        case .raw:
            List {
                ForEach(vm.rawRows) { row in
                    Section(row.key) {
                        Text(row.value).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
        }
    }
}

@available(iOS 15.0, *)
private struct FrameRow: View {
    let index: Int
    let text: String
    let inApp: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)").font(.caption2.monospacedDigit()).foregroundColor(.secondary).frame(width: 24, alignment: .trailing)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(inApp ? .semibold : .regular)
                .foregroundColor(inApp ? .primary : .secondary)
                .textSelection(.enabled)
        }
    }
}
