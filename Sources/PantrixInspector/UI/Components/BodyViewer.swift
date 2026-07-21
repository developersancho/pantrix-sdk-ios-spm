//
//  BodyViewer.swift
//  Pantrix
//
//  Shows a request/response body: the Kit pretty-prints it (§4h), this view displays it monospaced and
//  highlights find-in-body matches. Per the Phase 3 timebox this is the degraded variant — it HIGHLIGHTS
//  every match but does not auto-scroll to them (SwiftUI `Text` gives no layout result to scroll to). An
//  absent body shows its availability note, never a blank pane. iOS 15-gated.
//

import SwiftUI

@available(iOS 15.0, *)
struct BodyViewer: View {
    let text: String
    let isPresent: Bool
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isPresent {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                    TextField("Find in body", text: $query)
                        .font(.caption)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(6)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            ScrollView {
                Text(highlighted)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var highlighted: AttributedString {
        var attributed = AttributedString(text)
        guard isPresent, !query.isEmpty else { return attributed }
        let lowerText = text.lowercased()
        let needle = query.lowercased()
        var searchStart = lowerText.startIndex
        while let range = lowerText.range(of: needle, range: searchStart..<lowerText.endIndex) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = .yellow
                attributed[attrRange].foregroundColor = .black
            }
            searchStart = range.upperBound
        }
        return attributed
    }
}
