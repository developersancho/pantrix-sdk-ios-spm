//
//  EventsView.swift
//  Pantrix
//
//  The Events screen: a searchable, refreshable, filterable list grouped into session sections, under the
//  stats header. All behaviour lives in the Kit's `EventsViewModel` (tested); this view renders `state` and
//  forwards taps. iOS 15-gated (§4c).
//

import SwiftUI
import PantrixInspectorKit

@available(iOS 15.0, *)
struct EventsView: View {
    @StateObject private var vm: EventsViewModel
    @State private var showFilter = false

    init(viewModel: EventsViewModel) {
        _vm = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        InspectorStateContainer(state: vm.state, emptyMessage: "No events match") { sections in
            List {
                Section { DashboardStatsHeader(stats: vm.stats) }
                ForEach(sections) { section in
                    Section(header: sessionHeader(section)) {
                        ForEach(section.rows) { row in
                            NavigationLink { detail(for: row) } label: { EventRowView(row: row) }
                        }
                    }
                }
                if vm.canLoadMore {
                    Button("Load more…") { vm.loadMore() }
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: Binding(get: { vm.searchText }, set: { vm.setSearch($0) }), prompt: "Name, type or screen")
        .refreshable { vm.reload() }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showFilter = true } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
            }
        }
        .sheet(isPresented: $showFilter) { EventsFilterSheet(vm: vm, isPresented: $showFilter) }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    @ViewBuilder
    private func detail(for row: EventRowDisplay) -> some View {
        if let detailVM = vm.detailViewModel(for: row.id) {
            EventDetailView(vm: detailVM)
        } else {
            InspectorMessageView(symbol: "questionmark.circle", tint: .secondary, title: "Event not loaded", detail: nil)
        }
    }

    private func sessionHeader(_ section: EventSection) -> some View {
        HStack(spacing: 6) {
            if section.crashed {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.caption2)
            }
            Text(section.headerTitle)
            Spacer()
            if let duration = section.durationText {
                Text(duration).foregroundColor(.secondary)
            }
            Text("\(section.rows.count)").foregroundColor(.secondary)
        }
        .font(.caption)
    }
}

@available(iOS 15.0, *)
private struct EventRowView: View {
    let row: EventRowDisplay

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: SFSymbolMap.symbol(for: row.kind))
                .foregroundColor(InspectorPalette.color(for: row.kind))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.subheadline)
                HStack(spacing: 6) {
                    Text(row.clock).font(.caption2).foregroundColor(.secondary).monospacedDigit()
                    if let screen = row.screenName {
                        Text(screen).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            if row.isReported {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption2)
            }
        }
    }
}

@available(iOS 15.0, *)
private struct EventsFilterSheet: View {
    @ObservedObject var vm: EventsViewModel
    @Binding var isPresented: Bool
    @State private var selected: Set<String> = []
    @State private var reportedOnly = false

    var body: some View {
        NavigationView {
            Form {
                Section("Types") {
                    ForEach(EventKind.known, id: \.self) { kind in
                        Button {
                            toggle(kind)
                        } label: {
                            HStack {
                                Image(systemName: SFSymbolMap.symbol(for: kind)).foregroundColor(InspectorPalette.color(for: kind)).frame(width: 22)
                                Text(kind.wireValue)
                                Spacer()
                                if selected.contains(kind.wireValue) { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
                Section {
                    Toggle("Reported only", isOn: $reportedOnly)
                }
            }
            .navigationTitle("Filter")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") { selected = []; reportedOnly = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") { apply() }
                }
            }
        }
        .onAppear {
            selected = Set(vm.selectedTypes.map(\.wireValue))
            reportedOnly = vm.reportedOnly
        }
    }

    private func toggle(_ kind: EventKind) {
        if selected.contains(kind.wireValue) { selected.remove(kind.wireValue) } else { selected.insert(kind.wireValue) }
    }

    private func apply() {
        let types = EventKind.known.filter { selected.contains($0.wireValue) }
        vm.applyFilter(types: types, reportedOnly: reportedOnly)
        isPresented = false
    }
}
