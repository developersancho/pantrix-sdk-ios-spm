//
//  EventDetailView.swift
//  Pantrix
//
//  The event detail: the Kit's `EventDetailViewModel` sections rendered as `DisclosureGroup`s. First few
//  sections open by default; the payload stays collapsed. The view formats nothing (§4h). iOS 15-gated.
//

import SwiftUI
import PantrixInspectorKit

@available(iOS 15.0, *)
struct EventDetailView: View {
    @StateObject private var vm: EventDetailViewModel

    init(vm: EventDetailViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }

    var body: some View {
        List {
            ForEach(Array(vm.sections.enumerated()), id: \.element.id) { index, section in
                DisclosureGroup(isExpanded: expansion(index)) {
                    ForEach(section.rows) { row in
                        KeyValueRow(key: row.key, value: row.value)
                    }
                } label: {
                    Text(section.title).font(.headline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(vm.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Meta + the first context blobs open; heavier sections (payload) start collapsed.
    private func expansion(_ index: Int) -> Binding<Bool> {
        let key = vm.sections[index].id
        return Binding(
            get: { expanded[key] ?? (index < 2) },
            set: { expanded[key] = $0 }
        )
    }

    @State private var expanded: [String: Bool] = [:]
}
