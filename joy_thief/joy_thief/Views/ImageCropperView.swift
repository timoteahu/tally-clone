import SwiftUI
import UIKit

// Extension to properly handle image orientation
extension UIImage {
    func normalizedImage() -> UIImage {
        if imageOrientation == .up {
            return self
        }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return normalizedImage
    }
}

struct ImageCropperView: View {
    let originalImage: UIImage
    @Binding var isPresented: Bool
    let onCrop: (UIImage) -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    @Environment(\.colorScheme) var colorScheme
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    
    // Fix image orientation
    private var image: UIImage {
        return originalImage.normalizedImage()
    }
    
    var body: some View {
        ZStack {
            // Background that ignores safe area
            Color.black
                .ignoresSafeArea()
            
            // Main content that respects safe area
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Header
                    headerView
                        .background(Color.black.opacity(0.9))
                    
                    // Cropper Area
                    ZStack {
                        // Dark overlay
                        Color.black.opacity(0.8)
                        
                        // Image with circular mask
                        cropperContent(geometry: geometry)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Bottom controls
                    bottomControls
                        .padding(.bottom, 20)
                }
            }
            
            // Loading overlay
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Processing...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var headerView: some View {
        HStack {
            Button("cancel") {
                isPresented = false
            }
            .foregroundColor(.white)
            .font(.system(size: 17, weight: .regular))
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            Spacer()
            
            Text("move and scale")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.white)
            
            Spacer()
            
            Button("choose") {
                Task {
                    isProcessing = true
                    
                    // Simulate a small delay for visual feedback
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    
                    if let croppedImage = cropImage() {
                        onCrop(croppedImage)
                        isPresented = false
                    } else {
                        errorMessage = "Failed to process image. Please try again."
                        showError = true
                    }
                    
                    isProcessing = false
                }
            }
            .foregroundColor(.white)
            .font(.system(size: 17, weight: .medium))
            .padding(.horizontal)
            .padding(.vertical, 12)
            .disabled(isProcessing)
        }
    }
    
    private func cropperContent(geometry: GeometryProxy) -> some View {
        let cropSize = min(geometry.size.width, geometry.size.height) * 0.85
        
        return ZStack {
            // Dark background
            Color.black.opacity(0.8)
            
            // Image container
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: cropSize, height: cropSize)
                .scaleEffect(scale)
                .offset(offset)
                .mask(
                    Circle()
                        .frame(width: cropSize, height: cropSize)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: cropSize, height: cropSize)
                )
                .contentShape(Circle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                lastOffset = offset
                            }
                            let translation = value.translation
                            let newOffset = CGSize(
                                width: lastOffset.width + translation.width,
                                height: lastOffset.height + translation.height
                            )
                            offset = limitOffset(newOffset, cropSize: cropSize)
                        }
                        .onEnded { _ in
                            isDragging = false
                            lastOffset = offset
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = min(max(scale * delta, minScale), maxScale)
                            // Adjust offset after scaling to keep image within bounds
                            offset = limitOffset(offset, cropSize: cropSize)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                        }
                )
            
            // Grid overlay
            CircularGridOverlay(size: cropSize)
        }
    }
    
    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Zoom slider
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "minus.magnifyingglass")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 16))
                    
                    Slider(value: $scale, in: minScale...maxScale)
                        .accentColor(.white)
                        .onChange(of: scale) { oldValue, newValue in
                            // Adjust offset after scaling to keep image within bounds
                            offset = limitOffset(offset, cropSize: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.85)
                        }
                    
                    Image(systemName: "plus.magnifyingglass")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 16))
                }
                .padding(.horizontal, 40)
            }
            
            // Helper text
            Text("Pinch to zoom • Drag to reposition")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    private func limitOffset(_ proposedOffset: CGSize, cropSize: CGFloat) -> CGSize {
        let imageSize = image.size
        let imageAspectRatio = imageSize.width / imageSize.height
        
        // Calculate the actual displayed size of the image
        var displayedImageWidth: CGFloat
        var displayedImageHeight: CGFloat
        
        if imageAspectRatio > 1 {
            // Landscape image
            displayedImageHeight = cropSize
            displayedImageWidth = cropSize * imageAspectRatio
        } else {
            // Portrait or square image
            displayedImageWidth = cropSize
            displayedImageHeight = cropSize / imageAspectRatio
        }
        
        // Apply scale
        displayedImageWidth *= scale
        displayedImageHeight *= scale
        
        // Calculate the maximum offset that keeps the crop area covered
        let maxOffsetX = max(0, (displayedImageWidth - cropSize) / 2)
        let maxOffsetY = max(0, (displayedImageHeight - cropSize) / 2)
        
        // Clamp the offset to the allowed range
        return CGSize(
            width: min(max(proposedOffset.width, -maxOffsetX), maxOffsetX),
            height: min(max(proposedOffset.height, -maxOffsetY), maxOffsetY)
        )
    }
    
    private func cropImage() -> UIImage? {
        let cropSize: CGFloat = 1000 // Output size
        
        // Get the displayed crop size
        let displayCropSize = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.85
        
        // Calculate the actual crop rect in the original image
        let imageSize = image.size
        let imageAspectRatio = imageSize.width / imageSize.height
        
        // Calculate displayed image dimensions
        var displayedImageWidth: CGFloat
        var displayedImageHeight: CGFloat
        
        if imageAspectRatio > 1 {
            displayedImageHeight = displayCropSize
            displayedImageWidth = displayCropSize * imageAspectRatio
        } else {
            displayedImageWidth = displayCropSize
            displayedImageHeight = displayCropSize / imageAspectRatio
        }
        
        // Calculate scale factors
        let baseScaleX = imageSize.width / displayedImageWidth
        let baseScaleY = imageSize.height / displayedImageHeight
        
        // Calculate crop rectangle in image coordinates
        let scaledCropSize = displayCropSize * baseScaleX / scale
        let cropX = (imageSize.width - scaledCropSize) / 2 - (offset.width * baseScaleX / scale)
        let cropY = (imageSize.height - scaledCropSize) / 2 - (offset.height * baseScaleY / scale)
        
        let cropRect = CGRect(
            x: max(0, min(cropX, imageSize.width - scaledCropSize)),
            y: max(0, min(cropY, imageSize.height - scaledCropSize)),
            width: min(scaledCropSize, imageSize.width),
            height: min(scaledCropSize, imageSize.height)
        )
        
        // Crop the image (using normalized image which already has correct orientation)
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return nil }
        
        // Create UIImage preserving scale and orientation
        let croppedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
        
        // Create circular image with proper orientation
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Use 1.0 scale for consistent output
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cropSize, height: cropSize), format: format)
        
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: CGSize(width: cropSize, height: cropSize))
            
            // Save the current graphics state
            context.cgContext.saveGState()
            
            // Create circular clipping path
            context.cgContext.addEllipse(in: rect)
            context.cgContext.clip()
            
            // Draw the cropped image scaled to fill the output size
            croppedImage.draw(in: rect)
            
            // Restore graphics state
            context.cgContext.restoreGState()
        }
    }
}

// Circular grid overlay for better alignment
struct CircularGridOverlay: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Horizontal line
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: size, height: 0.5)
            
            // Vertical line
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 0.5, height: size)
            
            // Circle thirds
            ForEach([0.33, 0.67], id: \.self) { fraction in
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    .frame(width: size * fraction, height: size * fraction)
            }
        }
        .mask(Circle())
    }
}

// Preview provider
struct ImageCropperView_Previews: PreviewProvider {
    static var previews: some View {
        ImageCropperView(
            originalImage: UIImage(systemName: "person.circle.fill")!,
            isPresented: .constant(true)
        ) { _ in }
    }
}