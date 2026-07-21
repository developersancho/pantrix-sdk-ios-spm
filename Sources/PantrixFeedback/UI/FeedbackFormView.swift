//
//  FeedbackFormView.swift
//  Pantrix
//
//  The feedback form (Android `FeedbackScreen` parity): a preview of the captured screenshot, a message
//  field, and Send / Cancel. The optional "Annotate" affordance is wired in Phase 2 (`onEditScreenshot`);
//  when nil (Phase 1) it is hidden. Pure SwiftUI — no Kit `Domain` type is named here (layer rule §4h);
//  the message string is handed back to `FeedbackRuntime`, which composes + submits it.
//

import SwiftUI

/// Holds the (possibly annotated) screenshot so the form re-renders when the annotation editor updates it.
@available(iOS 15.0, *)
final class FeedbackFormModel: ObservableObject {
    @Published var screenshot: UIImage
    init(screenshot: UIImage) { self.screenshot = screenshot }
}

@available(iOS 15.0, *)
struct FeedbackFormView: View {
    @ObservedObject var model: FeedbackFormModel
    let onSend: (String) -> Void
    let onCancel: () -> Void
    var onEditScreenshot: (() -> Void)?

    @State private var message: String = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: model.screenshot)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 320)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
                        if let onEditScreenshot {
                            Button(action: onEditScreenshot) {
                                Label("Annotate", systemImage: "pencil.tip.crop.circle")
                                    .font(.footnote.bold())
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .padding(8)
                        }
                    }

                    Text("Message")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("What went wrong, or what could be better?")
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 8)
                        }
                        TextEditor(text: $message)
                            .frame(minHeight: 120)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                    }
                }
                .padding()
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { onSend(message) }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
