//
//  Runtime.swift
//  Pantrix
//
//  The single object behind the facade (§4c): it owns the store, checks the release gate, and builds the
//  inspector view controller. `@available(iOS 15.0, *)` and `@MainActor` — the facade reaches it only from
//  inside `if #available(iOS 15.0, *)`, so below iOS 15 nothing here is touched.
//

import UIKit
import SwiftUI
import PantrixInspectorKit

@available(iOS 15.0, *)
@MainActor
final class Runtime {
    static let shared = Runtime()

    private var config = InspectorConfiguration()
    private var gate = ReleaseGate()
    private var store: InspectorStore?
    private weak var presented: UIViewController?
    private let sceneObserver = InspectorSceneObserver()
    private var overlayWindow: OverlayWindow?

    private init() {}

    func enable(_ config: InspectorConfiguration) {
        self.config = config
        guard isAvailable else { return }   // no affordances in a gated-off build

        if config.enablesShakeToOpen {
            // Present from the scene of the window that actually received the shake — so shake-to-open works
            // on its own, without the bubble-only scene observer (which a shake-only host never starts).
            ShakeSwizzler.install { [weak self] window in
                Task { @MainActor in
                    guard let scene = window.windowScene else { return }
                    self?.present(inScene: scene)
                }
            }
        }
        if config.showsFloatingBubble {
            sceneObserver.start { [weak self] scene in self?.attachBubble(to: scene) }
        }
    }

    private func attachBubble(to scene: UIWindowScene) {
        guard overlayWindow == nil else { return }   // one bubble
        // The bubble opens the inspector on ITS OWN scene — captured here, not read back from a tracked
        // "active scene" — so presentation never depends on notification timing.
        overlayWindow = OverlayWindow(windowScene: scene) { [weak self] in self?.present(inScene: scene) }
    }

    /// Presents from the frontmost view controller of `scene`'s HOST window — never our own overlay window.
    /// A bubble tap can make the overlay the key window; presenting on it would route the inspector's touches
    /// into `OverlayWindow.hitTest`, which returns nil off the bubble, so nothing in the inspector would be
    /// tappable. `OverlayPresentation.hostIndex` excludes the overlay by identity.
    private func present(inScene scene: UIWindowScene) {
        let windows = scene.windows
        let candidates = windows.map {
            OverlayWindowCandidate(isKey: $0.isKeyWindow, isOverlay: $0 === overlayWindow)
        }
        guard let index = OverlayPresentation.hostIndex(candidates),
              let root = windows[index].rootViewController else { return }
        windows[index].makeKey()   // the bubble tap may have stolen key; give it back to the host
        present(from: root)
    }

    /// Whether the inspector will actually open in this build — the gate result. The facade forwards this.
    var isAvailable: Bool {
        gate.isAvailable(allowsInReleaseBuilds: config.allowsInReleaseBuilds)
    }

    /// A view controller hosting the inspector, or `nil` when the gate rejects the build or the store can't
    /// be located. `nil` is the gate's only signal — the facade never force-unwraps. The returned controller
    /// is tracked as `presented`, so its built-in Close button works even when a host presents it itself.
    func makeViewController() -> UIViewController? {
        guard isAvailable, let store = ensureStore() else { return nil }
        store.start()   // one polling lifecycle shared by every screen's view-model
        let models = InspectorTabModels(
            events: EventsViewModel(store: store),
            network: NetworkListViewModel(store: store),
            crashes: CrashListViewModel(store: store),
            performance: PerformanceViewModel(store: store),
            device: DeviceViewModel(store: store),
            timeline: TimelineViewModel(store: store),
            pipeline: PipelineViewModel(store: store, processStartEpochMillis: ProcessStart.epochMillis())
        )
        let root = InspectorRootView(models: models, onClose: { [weak self] in self?.dismiss() })
        // A named subclass (not a bare UIHostingController) so PantrixCore's automatic screen tracking skips
        // it by the reserved `PantrixInspector` class-name prefix — the inspector must not appear as an app
        // screen in the very data it inspects.
        let host = PantrixInspectorHostController(rootView: root)
        host.modalPresentationStyle = .fullScreen
        presented = host   // track for dismiss()/Close on every path, and to guard against double-present
        return host
    }

    /// Presents the inspector from the top-most view controller reachable from `presenter`. A no-op when the
    /// inspector is already showing, so a second shake/tap can't stack a duplicate that orphans the first.
    func present(from presenter: UIViewController) {
        guard presented == nil, let vc = makeViewController() else { return }
        var top = presenter
        while let next = top.presentedViewController { top = next }
        overlayWindow?.isHidden = true   // don't let the bubble float over — or block touches to — the inspector
        top.present(vc, animated: true)
    }

    func dismiss() {
        presented?.dismiss(animated: true)
        presented = nil
        store?.stop()   // pause polling while the inspector is closed
        overlayWindow?.isHidden = false   // bring the bubble back once the inspector is gone
    }

    private func ensureStore() -> InspectorStore? {
        if let store { return store }
        guard let repository = InspectorRepository.atDefaultLocation() else { return nil }
        let store = InspectorStore(repository: repository)
        self.store = store
        return store
    }
}

/// Hosts the inspector's SwiftUI root. The ONLY reason it's a named subclass rather than a bare
/// `UIHostingController` is its class name: PantrixCore's automatic screen tracking skips any controller
/// whose class name starts with `PantrixInspector`, so the inspector never records itself as an app screen
/// (which would pollute the very screen-attribution data it exists to inspect).
@available(iOS 15.0, *)
final class PantrixInspectorHostController: UIHostingController<InspectorRootView> {}

/// This process's start time as epoch milliseconds, read from the kernel — so the Pipeline view can gate an
/// `app_exit` row to THIS launch. Impure (lives in the view target, outside the tested Kit); `nil` if the
/// sysctl fails, which the Kit's `LaunchScopedEvent` treats as "can't place in time → stale".
@available(iOS 15.0, *)
enum ProcessStart {
    static func epochMillis() -> Int64? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        let seconds = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return Int64(seconds * 1000)
    }
}
