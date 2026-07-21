//
//  NetworkDetailView.swift
//  Pantrix
//
//  One transaction across 4 segments (Overview / Request / Response / Timing), with an Export menu that
//  shares any of the five formats. Redaction + availability labels come from the Kit's resolver, so the
//  screen and the exports agree. iOS 15-gated (§4c).
//

import SwiftUI
import PantrixInspectorKit

@available(iOS 15.0, *)
struct NetworkDetailView: View {
    @StateObject private var vm: NetworkDetailViewModel
    @State private var segment: Segment = .overview
    @State private var share: IdentifiedArtifact?

    init(vm: NetworkDetailViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }

    private enum Segment: String, CaseIterable { case overview = "Overview", request = "Request", response = "Response", timing = "Timing" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            content
        }
        .navigationTitle("\(vm.method) \(vm.statusCode == 0 ? "" : String(vm.statusCode))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(NetworkDetailViewModel.ExportFormat.allCases, id: \.self) { format in
                        Button(format.rawValue) { share = IdentifiedArtifact(artifact: vm.export(format)) }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $share) { InspectorShareSheet(artifact: $0.artifact) }
    }

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .overview:
            List { rows(vm.overviewRows) }
        case .request:
            List {
                Section("Headers") { rows(vm.requestHeaderRows) }
                Section("Body") { BodyViewer(text: vm.bodyDisplay(vm.requestBody), isPresent: vm.requestBody.hasContent) }
            }
        case .response:
            List {
                Section("Headers") { rows(vm.responseHeaderRows) }
                Section("Body") { BodyViewer(text: vm.bodyDisplay(vm.responseBody), isPresent: vm.responseBody.hasContent) }
            }
        case .timing:
            List { rows(vm.timingRows) }
        }
    }

    private func rows(_ rows: [DetailRow]) -> some View {
        ForEach(rows) { KeyValueRow(key: $0.key, value: $0.value) }
    }
}

/// Wraps a `ShareArtifact` so `.sheet(item:)` can present it (two exports may share a filename).
@available(iOS 15.0, *)
struct IdentifiedArtifact: Identifiable {
    let id = UUID()
    let artifact: ShareArtifact
}
