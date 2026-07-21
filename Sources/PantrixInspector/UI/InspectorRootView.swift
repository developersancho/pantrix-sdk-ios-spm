//
//  InspectorRootView.swift
//  Pantrix
//
//  The inspector's tab shell. The tab set is built from the routes ACTUALLY shipped this phase — no empty
//  "coming soon" tab (§7 / Phase 2): shipping a placeholder would disprove "each phase ships independently",
//  not support it. Phase 2 ships only Events; Network/Crashes/System are appended in Phases 3/4/5.
//  iOS 15-gated (§4c).
//

import SwiftUI
import PantrixInspectorKit

/// A shipped inspector tab.
@available(iOS 15.0, *)
enum InspectorRoute: String, CaseIterable {
    case events
    case network
    case crashes
    case system

    /// The tabs shipped so far — the full set as of Phase 5.
    static let shipped: [InspectorRoute] = [.events, .network, .crashes, .system]

    var title: String {
        switch self {
        case .events: return "Events"
        case .network: return "Network"
        case .crashes: return "Crashes"
        case .system: return "System"
        }
    }

    var symbol: String {
        switch self {
        case .events: return "list.bullet.rectangle"
        case .network: return "network"
        case .crashes: return "exclamationmark.triangle"
        case .system: return "cpu"
        }
    }
}

/// All the tab view-models, built by `Runtime` (which holds the store); passed to the view as one bundle so
/// the shell doesn't take a dozen init parameters.
@available(iOS 15.0, *)
@MainActor
struct InspectorTabModels {
    let events: EventsViewModel
    let network: NetworkListViewModel
    let crashes: CrashListViewModel
    let performance: PerformanceViewModel
    let device: DeviceViewModel
    let timeline: TimelineViewModel
    let pipeline: PipelineViewModel
}

@available(iOS 15.0, *)
struct InspectorRootView: View {
    let models: InspectorTabModels
    let onClose: () -> Void

    var body: some View {
        TabView {
            ForEach(InspectorRoute.shipped, id: \.self) { route in
                tab(route)
                    .tabItem { Label(route.title, systemImage: route.symbol) }
            }
        }
    }

    @ViewBuilder
    private func tab(_ route: InspectorRoute) -> some View {
        switch route {
        case .events:
            navigation("Events") { EventsView(viewModel: models.events) }
        case .network:
            navigation("Network") { NetworkListView(viewModel: models.network) }
        case .crashes:
            navigation("Crashes") { CrashListView(viewModel: models.crashes) }
        case .system:
            navigation("System") {
                SystemView(performance: models.performance, device: models.device,
                           timeline: models.timeline, pipeline: models.pipeline)
            }
        }
    }

    private func navigation<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        NavigationView {
            content()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close", action: onClose)
                    }
                }
        }
        .navigationViewStyle(.stack)
    }
}
