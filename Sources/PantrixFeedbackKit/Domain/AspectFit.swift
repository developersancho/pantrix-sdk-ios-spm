//
//  AspectFit.swift
//  Pantrix
//
//  The pure geometry the annotation editor needs: where a screenshot sits when shown aspect-fit inside a
//  container. The PencilKit canvas is laid over EXACTLY this rect so a stroke lands on the pixel the user
//  touched; the export then scales the drawing from this rect back to the screenshot's native size. Kept in
//  the Kit so the arithmetic — the part that decides whether an annotation aligns with the image — is tested.
//

import CoreGraphics

public enum AspectFit {
    /// The centered, letterboxed rect an image of `imageSize` occupies when scaled to FIT inside `bounds`
    /// (never cropped). `.zero` for a degenerate (non-positive) input.
    public static func rect(imageSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }
}
