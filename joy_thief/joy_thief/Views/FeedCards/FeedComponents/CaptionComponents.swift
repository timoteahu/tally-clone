import SwiftUI

// MARK: - Caption Editing View
struct CaptionEditingView: View {
    @Binding var editingCaption: String
    let isUpdatingCaption: Bool
    @Binding var isCommentFieldFocused: Bool
    let cardWidth: CGFloat
    let onUpdate: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            captionTextField
            captionEditingButtons
        }
        .padding(.all, 12)
        .background(captionEditingBackground)
        .onTapGesture {
            // Prevent tap from bubbling up
        }
    }
    
    private var captionTextField: some View {
        TextField("Add a caption...", text: $editingCaption, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.ebGaramondCaption)
            .foregroundColor(.white)
            .lineLimit(2...4)
            .onSubmit {
                onUpdate()
            }
            .onTapGesture {
                // Prevent tap from bubbling up
                isCommentFieldFocused = true
            }
    }
    
    private var captionEditingButtons: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                onCancel()
            }
            .font(.ebGaramondCaption)
            .foregroundColor(.white.opacity(0.7))
            
            Button(isUpdatingCaption ? "Saving..." : "Save") {
                onUpdate()
            }
            .font(.ebGaramondCaption)
            .foregroundColor(.blue)
            .disabled(isUpdatingCaption)
            
            Spacer()
        }
    }
    
    private var captionEditingBackground: some View {
        RoundedRectangle(cornerRadius: cardWidth * 0.025)
            .fill(Color.blue.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: cardWidth * 0.025)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Caption Display View
struct CaptionDisplayView: View {
    let caption: String?
    let isCurrentUserPost: Bool
    let onStartEditing: (String) -> Void
    
    var body: some View {
        Group {
            if let caption = caption, !caption.isEmpty {
                existingCaptionView(caption)
            } else if isCurrentUserPost {
                addCaptionPrompt
            } else {
                EmptyView()
            }
        }
    }
    
    private func existingCaptionView(_ caption: String) -> some View {
        Text(caption)
            .font(.ebGaramondCaption)
            .foregroundColor(.white.opacity(0.8))
            .lineLimit(2)
            .onTapGesture {
                if isCurrentUserPost {
                    onStartEditing(caption)
                }
            }
    }
    
    private var addCaptionPrompt: some View {
        Text("Tap to add caption")
            .font(.ebGaramondCaption)
            .foregroundColor(.white.opacity(0.5))
            .italic()
            .onTapGesture {
                onStartEditing("")
            }
    }
} 