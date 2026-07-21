//
//  CrashListView.swift
//  Pantrix
//
//  The Crashes screen: a stats card + All/Fatal/Handled/ANR filter chips (with counts), then the crash
//  rows. Each row shows its kind, exception type, and a monospaced blame-frame preview. Fatal crashes are
//  red-tinted. Behaviour is in the Kit's `CrashListViewModel`. iOS 15-gated (§4c).
//

import SwiftUI
import PantrixInspectorKit

@available(iOS 15.0, *)
struct CrashListView: View {
    @StateObject private var vm: CrashListViewModel

    init(viewModel: CrashListViewModel) {
        _vm = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            InspectorStateContainer(state: vm.state, emptyMessage: "No crashes 🎉") { rows in
                List {
                    ForEach(rows) { row in
                        NavigationLink { detail(for: row) } label: { CrashRowView(row: row) }
                    }
                    if vm.canLoadMore {
                        Button("Load more…") { vm.loadMore() }.frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", count: vm.stats.total, kind: nil)
                ForEach(CrashKind.allCases, id: \.self) { kind in
                    chip(kind.label, count: vm.stats.count(kind), kind: kind)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ label: String, count: Int, kind: CrashKind?) -> some View {
        let selected = vm.filter == kind
        return Button {
            vm.setFilter(kind)
        } label: {
            Text("\(label) \(count)")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background((selected ? color(kind) : Color(.secondarySystemBackground)), in: Capsule())
                .foregroundColor(selected ? .white : .primary)
        }
    }

    private func color(_ kind: CrashKind?) -> Color {
        switch kind {
        case .fatal: return .red
        case .handled: return .orange
        case .anr: return .purple
        case nil: return .accentColor
        }
    }

    @ViewBuilder
    private func detail(for row: CrashRowDisplay) -> some View {
        if let detailVM = vm.detailViewModel(for: row.id) {
            CrashDetailView(vm: detailVM)
        } else {
            InspectorMessageView(symbol: "questionmark.circle", tint: .secondary, title: "Crash not loaded", detail: nil)
        }
    }
}

@available(iOS 15.0, *)
private struct CrashRowView: View {
    let row: CrashRowDisplay

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.isFatal ? "exclamationmark.octagon.fill" : "exclamationmark.triangle")
                .foregroundColor(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(row.title).font(.subheadline.weight(.semibold))
                    StatusPill(text: row.kind.label, color: tint)
                }
                if !row.message.isEmpty {
                    Text(row.message).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
                if let blame = row.blamePreview {
                    Text(blame).font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
                }
                Text(row.clock).font(.caption2).foregroundColor(.secondary).monospacedDigit()
            }
        }
    }

    private var tint: Color {
        switch row.kind {
        case .fatal: return .red
        case .handled: return .orange
        case .anr: return .purple
        }
    }
}
