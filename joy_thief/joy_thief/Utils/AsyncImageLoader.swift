import UIKit
import SwiftUI

/// Utility for loading images asynchronously off the main thread
@MainActor
class AsyncImageLoader {
    static let shared = AsyncImageLoader()
    
    private init() {}
    
    /// Load UIImage from data asynchronously
    static func loadImage(from data: Data) async -> UIImage? {
        return await Task.detached {
            UIImage(data: data)
        }.value
    }
    
    /// Load and resize image asynchronously
    static func loadAndResize(data: Data, targetSize: CGSize) async -> UIImage? {
        return await Task.detached {
            guard let image = UIImage(data: data) else { return nil }
            return image.resize(to: targetSize)
        }.value
    }
    
    /// Load image from URL asynchronously
    static func loadImage(from url: URL) async throws -> UIImage? {
        let (data, _) = try await URLSession.shared.data(from: url)
        return await loadImage(from: data)
    }
}

// MARK: - UIImage Extensions

extension UIImage {
    /// Resize image to target size efficiently
    func resize(to targetSize: CGSize) -> UIImage? {
        let size = self.size
        
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        
        // Choose the smaller ratio to maintain aspect ratio
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let rect = CGRect(origin: .zero, size: newSize)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        self.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
}

// MARK: - SwiftUI View Extension

extension View {
    /// Load image asynchronously in SwiftUI views
    func asyncImage(from data: Data?, placeholder: Image = Image(systemName: "photo")) -> some View {
        AsyncImageView(imageData: data, placeholder: placeholder)
    }
}

// MARK: - Async Image View

struct AsyncImageView: View {
    let imageData: Data?
    let placeholder: Image
    
    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let uiImage = loadedImage {
                Image(uiImage: uiImage)
                    .resizable()
            } else {
                placeholder
                    .foregroundColor(.gray.opacity(0.3))
            }
        }
        .task {
            await loadImage()
        }
        .onChange(of: imageData) { _, newData in
            Task {
                await loadImage()
            }
        }
    }
    
    private func loadImage() async {
        guard !isLoading, let data = imageData else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        if let image = await AsyncImageLoader.loadImage(from: data) {
            loadedImage = image
        }
    }
}