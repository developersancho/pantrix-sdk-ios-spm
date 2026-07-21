//
//  NetworkListView.swift
//  Pantrix
//
//  The Network screen: `pntrx_network`, newest first, searchable + paginated + live. Behaviour is in the
//  Kit's `NetworkListViewModel`; this renders `state`. iOS 15-gated (§4c).
//

import SwiftUI
import PantrixInspectorKit

@available(iOS 15.0, *)
struct NetworkListView: View {
    @StateObject private var vm: NetworkListViewModel

    init(viewModel: NetworkListViewModel) {
        _vm = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        InspectorStateContainer(state: vm.state, emptyMessage: "No network requests") { rows in
            List {
                ForEach(rows) { row in
                    NavigationLink { detail(for: row) } label: { NetworkRowView(row: row) }
                }
                if vm.canLoadMore {
                    Button("Load more…") { vm.loadMore() }
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: Binding(get: { vm.searchText }, set: { vm.searchText = $0 }), prompt: "URL, method or status")
        .refreshable { vm.reload() }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    @ViewBuilder
    private func detail(for row: NetworkRowDisplay) -> some View {
        if let detailVM = vm.detailViewModel(for: row.id) {
            NetworkDetailView(vm: detailVM)
        } else {
            InspectorMessageView(symbol: "questionmark.circle", tint: .secondary, title: "Request not loaded", detail: nil)
        }
    }
}

@available(iOS 15.0, *)
private struct NetworkRowView: View {
    let row: NetworkRowDisplay

    var body: some View {
        HStack(spacing: 10) {
            Text(row.method)
                .font(.caption2.weight(.bold))
                .frame(width: 48, alignment: .leading)
                .foregroundColor(methodColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.url).font(.subheadline).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(row.clock).font(.caption2).foregroundColor(.secondary).monospacedDigit()
                    Text(row.durationText).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            StatusPill(text: row.statusCode == 0 ? "—" : "\(row.statusCode)", color: statusColor)
        }
    }

    private var statusColor: Color {
        if row.isError { return .red }
        if row.statusCode >= 300 { return .orange }
        return .green
    }

    private var methodColor: Color {
        switch row.method {
        case "GET": return .green
        case "POST": return .blue
        case "PUT", "PATCH": return .orange
        case "DELETE": return .red
        default: return .secondary
        }
    }
}
