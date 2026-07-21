//
//  InspectorShareSheet.swift
//  Pantrix
//
//  Presents a Kit `ShareArtifact` through `UIActivityViewController`. The artifact is written to a temp file
//  (so the share sheet offers "Save to Files", AirDrop, etc. with the right filename), and stale exports
//  (>1h) are pruned first. On iPad the popover anchor is REQUIRED — without it `UIActivityViewController`
//  crashes. iOS 15-gated (§4c).
//

import SwiftUI
import UIKit
import PantrixInspectorKit

@available(iOS 15.0, *)
struct InspectorShareSheet: UIViewControllerRepresentable {
    let artifact: ShareArtifact

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let url = ShareArtifactWriter.write(artifact)
        let items: [Any] = url.map { [$0] } ?? [artifact.content]
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad: `UIActivityViewController` REQUIRES a popover anchor or UIKit raises. Anchor to the
        // controller's own view centre — valid, and it never crashes.
        if let pop = controller.popoverPresentationController {
            pop.sourceView = controller.view
            pop.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Writes a `ShareArtifact` to a temp file and prunes exports older than an hour.
@available(iOS 15.0, *)
enum ShareArtifactWriter {
    static func write(_ artifact: ShareArtifact) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pantrix-inspector-exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        prune(dir)
        let url = dir.appendingPathComponent(artifact.filename)
        do {
            try artifact.data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil   // fall back to sharing the raw string
        }
    }

    private static func prune(_ dir: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        for file in files {
            if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
