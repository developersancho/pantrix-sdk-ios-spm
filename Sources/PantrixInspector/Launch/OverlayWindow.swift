//
//  OverlayWindow.swift
//  Pantrix
//
//  A floating draggable bubble in an extra window above the host (§4d). Four things that each break the
//  overlay if missed, all handled here: it's built with a `windowScene` (a scene-less window is invisible on
//  iOS 13+), it is NEVER made key (that would steal the host's keyboard/first-responder), the whole thing is
//  retained by the caller (a released window deallocates), and `hitTest` returns `nil` off the bubble so
//  every other touch falls through to the host. iOS 15-gated (§4c).
//

import UIKit
import PantrixInspectorKit

@available(iOS 15.0, *)
final class OverlayWindow: UIWindow {
    private let host: PantrixInspectorBubbleController

    init(windowScene: UIWindowScene, onTap: @escaping () -> Void) {
        host = PantrixInspectorBubbleController(onTap: onTap)
        super.init(windowScene: windowScene)
        windowLevel = .alert + 1
        backgroundColor = .clear
        rootViewController = host
        isHidden = false   // visible, but NOT key — never call makeKeyAndVisible()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Only the bubble consumes touches; everything else passes through to the host below.
        let bubbleFrame = host.bubble.convert(host.bubble.bounds, to: self)
        guard BubbleGeometry.hitsBubble(point: point, bubbleFrame: bubbleFrame) else { return nil }
        return super.hitTest(point, with: event)
    }
}

// Named with the reserved `PantrixInspector` prefix so PantrixCore's automatic screen tracking skips it —
// otherwise the bubble's own view controller would be recorded as an app "screen" the moment it appears,
// misattributing every subsequent event to it.
@available(iOS 15.0, *)
private final class PantrixInspectorBubbleController: UIViewController {
    let bubble = UIButton(type: .system)
    private let onTap: () -> Void
    private var dragStartCenter: CGPoint = .zero

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        // A passthrough container — the window's hitTest already gates touches, this just holds the bubble.
        view = UIView()
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let size: CGFloat = 56
        bubble.frame = CGRect(x: 0, y: 0, width: size, height: size)
        bubble.backgroundColor = UIColor.systemIndigo
        bubble.tintColor = .white
        bubble.setImage(UIImage(systemName: "ladybug.fill"), for: .normal)
        bubble.layer.cornerRadius = size / 2
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.3
        bubble.layer.shadowRadius = 6
        bubble.layer.shadowOffset = CGSize(width: 0, height: 2)
        bubble.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        bubble.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
        view.addSubview(bubble)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if bubble.center == CGPoint(x: 28, y: 28) || dragStartCenter == .zero {
            // Initial resting spot: lower-right, snapped.
            bubble.center = BubbleGeometry.snapped(
                center: CGPoint(x: view.bounds.maxX, y: view.bounds.maxY - 120),
                bubbleSize: bubble.bounds.size, in: view.bounds.inset(by: view.safeAreaInsets))
        }
    }

    @objc private func tapped() { onTap() }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            dragStartCenter = bubble.center
        case .changed:
            bubble.center = CGPoint(x: dragStartCenter.x + translation.x, y: dragStartCenter.y + translation.y)
        case .ended, .cancelled:
            let bounds = view.bounds.inset(by: view.safeAreaInsets)
            let target = BubbleGeometry.snapped(center: bubble.center, bubbleSize: bubble.bounds.size, in: bounds)
            UIView.animate(withDuration: 0.2) { self.bubble.center = target }
        default:
            break
        }
    }
}
