import SwiftUI

struct IdentitySnapshotPreviewView: View {
    let image: UIImage?
    @Binding var isPresented: Bool
    let onSubmit: (UIImage) -> Void
    let onRetake: () -> Void
    
    var body: some View {
        ZStack {
            // Dark background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    
                    Spacer()
                    
                    Text("Review Identity Snapshot")
                        .font(.custom("EBGaramond-Regular", size: 20))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Invisible spacer for centering
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal)
                .padding(.top, 50)
                
                Spacer()
                
                // Image preview
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 400)
                        .cornerRadius(20)
                        .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Instructions
                Text("Make sure your face is clearly visible")
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 30)
                
                // Action buttons
                HStack(spacing: 20) {
                    // Retake button
                    Button(action: {
                        isPresented = false
                        onRetake()
                    }) {
                        HStack {
                            Image(systemName: "camera.rotate")
                                .font(.system(size: 18))
                            Text("Retake")
                                .font(.custom("EBGaramond-Regular", size: 16))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.2))
                        )
                    }
                    
                    // Submit button
                    Button(action: {
                        if let image = image {
                            onSubmit(image)
                            isPresented = false
                        }
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                            Text("Use This Photo")
                                .font(.custom("EBGaramond-Regular", size: 16))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    IdentitySnapshotPreviewView(
        image: UIImage(systemName: "person.circle.fill"),
        isPresented: .constant(true),
        onSubmit: { _ in },
        onRetake: { }
    )
}