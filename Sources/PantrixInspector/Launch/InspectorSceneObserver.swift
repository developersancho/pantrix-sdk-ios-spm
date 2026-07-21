//
//  InspectorSceneObserver.swift
//  Pantrix
//
//  Tracks the active foreground `UIWindowScene` via `UIScene` notifications — NOT `UIApplication.shared
//  .connectedScenes`, which the SDK deliberately never touches (§4d) and which is a `Set` that can hold
//  several active scenes on iPad. The notification's `object` IS the scene. Used to attach the overlay
//  bubble to whichever scene is frontmost. iOS 15-gated (§4c).
//

import UIKit

@available(iOS 15.0, *)
@MainActor
final class InspectorSceneObserver: NSObject {
    private(set) var activeScene: UIWindowScene?
    private var onSceneActive: ((UIWindowScene) -> Void)?

    /// Begin observing; `handler` fires whenever a scene becomes active (immediately for an already-active
    /// one is the caller's job — at `enable()` time there may be no scene yet).
    func start(onSceneActive handler: @escaping (UIWindowScene) -> Void) {
        onSceneActive = handler
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sceneDidActivate(_:)), name: UIScene.didActivateNotification, object: nil)
        center.addObserver(self, selector: #selector(sceneDidDisconnect(_:)), name: UIScene.didDisconnectNotification, object: nil)
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        onSceneActive = nil
        activeScene = nil
    }

    @objc private func sceneDidActivate(_ note: Notification) {
        guard let scene = note.object as? UIWindowScene else { return }
        activeScene = scene
        onSceneActive?(scene)
    }

    @objc private func sceneDidDisconnect(_ note: Notification) {
        if let scene = note.object as? UIWindowScene, scene === activeScene { activeScene = nil }
    }
}
