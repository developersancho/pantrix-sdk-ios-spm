//
//  PantrixFeedbackAnnotationController.swift
//  Pantrix
//
//  The screenshot annotation editor (Android `ScreenshotAnnotationScreen` parity) — a PencilKit `PKCanvasView`
//  laid EXACTLY over the aspect-fit screenshot, with a minimal toolbar (undo, clear, three pen colours). On
//  Done it composites the screenshot + the drawing into one image and hands it back. PencilKit gives the pen,
//  finger+stylus input, and per-stroke undo for free — none of Android's custom `Path` bookkeeping.
//
//  Named with the reserved `PantrixFeedback` prefix so PantrixCore's screen tracking skips it (§4i).
//

import UIKit
import PencilKit
import PantrixFeedbackKit

@available(iOS 15.0, *)
final class PantrixFeedbackAnnotationController: UIViewController {
    private let screenshot: UIImage
    private let onDone: (UIImage) -> Void
    private let onCancel: () -> Void

    private let content = UIView()
    private let imageView = UIImageView()
    private let canvas = PKCanvasView()
    private var penColor: AnnotationColor = .default { didSet { applyTool() } }
    private let penWidth: CGFloat = 8
    // A dedicated undo manager for the pen strokes. PencilKit finds it up the responder chain (canvas →
    // this controller's `undoManager`) and registers stroke undos with it. It MUST be a stored manager, NOT
    // `canvas.undoManager`: the canvas has no undo manager of its own, so `canvas.undoManager` walks the
    // chain back to this controller — returning it here would recurse forever and overflow the stack.
    private let strokeUndoManager = UndoManager()

    init(screenshot: UIImage, onDone: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.screenshot = screenshot
        self.onDone = onDone
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Annotate"

        // OPAQUE bars + a neutral backdrop. The screenshot is often full of blue UI (buttons, links), so a
        // translucent bar let the blue Cancel/Done blend right into it — impossible to tell control from
        // content. Solid bars put the controls on their own chrome, and the shot sits BETWEEN them (see
        // viewDidLayoutSubviews), never under them.
        view.backgroundColor = .secondarySystemBackground
        let opaqueNav = UINavigationBarAppearance()
        opaqueNav.configureWithOpaqueBackground()
        navigationItem.standardAppearance = opaqueNav
        navigationItem.scrollEdgeAppearance = opaqueNav
        navigationItem.compactAppearance = opaqueNav
        let opaqueToolbar = UIToolbarAppearance()
        opaqueToolbar.configureWithOpaqueBackground()
        navigationController?.toolbar.standardAppearance = opaqueToolbar
        navigationController?.toolbar.scrollEdgeAppearance = opaqueToolbar

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        done.style = .done   // bold, so "Done" reads as the primary action
        navigationItem.rightBarButtonItem = done

        imageView.contentMode = .scaleAspectFit
        imageView.image = screenshot
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        applyTool()

        content.addSubview(imageView)
        content.addSubview(canvas)
        view.addSubview(content)

        setupToolbar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The content sits in the SAFE AREA — i.e. between the opaque nav bar and toolbar — so the screenshot
        // never slides under the controls.
        content.frame = view.bounds.inset(by: view.safeAreaInsets)
        // The canvas must overlay the image PIXEL-for-PIXEL, so both take the aspect-fit rect (not the full
        // bounds) — otherwise a stroke lands off the picture.
        let fit = AspectFit.rect(imageSize: screenshot.size, in: content.bounds.size)
        imageView.frame = fit
        canvas.frame = fit
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        navigationController?.setToolbarHidden(false, animated: false)
        let undo = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.backward"), style: .plain, target: self, action: #selector(undoTapped))
        let clear = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(clearTapped))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let swatches = AnnotationColor.allCases.map { colorItem($0) }
        toolbarItems = [undo, clear, flex] + swatches
        refreshSwatches()
    }

    private var swatchItems: [AnnotationColor: UIBarButtonItem] = [:]

    private func colorItem(_ color: AnnotationColor) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: swatchImage(color, selected: false), style: .plain, target: self, action: #selector(colorTapped(_:)))
        item.tag = AnnotationColor.allCases.firstIndex(of: color) ?? 0
        item.tintColor = uiColor(color)
        swatchItems[color] = item
        return item
    }

    private func refreshSwatches() {
        for (color, item) in swatchItems {
            item.image = swatchImage(color, selected: color == penColor)
        }
    }

    /// A filled circle for the colour; the selected one gets a ring so it's obvious which pen is active.
    private func swatchImage(_ color: AnnotationColor, selected: Bool) -> UIImage? {
        UIImage(systemName: selected ? "largecircle.fill.circle" : "circle.fill")
    }

    // MARK: - Actions

    @objc private func undoTapped() { strokeUndoManager.undo() }
    @objc private func clearTapped() { canvas.drawing = PKDrawing() }

    @objc private func colorTapped(_ sender: UIBarButtonItem) {
        penColor = AnnotationColor.allCases[sender.tag]
        refreshSwatches()
    }

    @objc private func cancelTapped() { onCancel() }

    @objc private func doneTapped() { onDone(mergedImage()) }

    // MARK: - Ink + export

    private func applyTool() {
        canvas.tool = PKInkingTool(.pen, color: uiColor(penColor), width: penWidth)
    }

    private func uiColor(_ color: AnnotationColor) -> UIColor {
        let c = color.rgb
        return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    /// The screenshot with the drawing composited on top, at the screenshot's native size/scale — so the
    /// e-mail attachment is full resolution regardless of the on-screen (aspect-fit) size.
    private func mergedImage() -> UIImage {
        let size = screenshot.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = screenshot.scale
        let drawing = canvas.drawing.image(from: canvas.bounds, scale: screenshot.scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            screenshot.draw(in: CGRect(origin: .zero, size: size))
            drawing.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// PencilKit resolves its undo manager up the responder chain; return our STORED one (never
    /// `canvas.undoManager`, which would recurse back here). This is what makes `strokeUndoManager` the
    /// manager the canvas registers strokes with, so the Undo button and the pen agree.
    override var undoManager: UndoManager? { strokeUndoManager }
}
