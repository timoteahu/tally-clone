import Foundation
import UIKit
import Combine

// Wrapper class to store both image and its key for tracking evictions
private class ImageWrapper: NSObject {
    let image: UIImage
    let key: String
    
    init(image: UIImage, key: String) {
        self.image = image
        self.key = key
    }
}

@MainActor
final class AvatarImageStore: NSObject, ObservableObject {
    static let shared = AvatarImageStore()
    
    // Use NSCache for automatic memory management
    private let imageCache = NSCache<NSString, ImageWrapper>()
    
    // Keep track of keys for UI updates
    @Published private(set) var cachedKeys = Set<String>()
    
    override private init() {
        super.init()
        
        // Configure cache limits
        imageCache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
        imageCache.countLimit = 100 // Max 100 images
        imageCache.delegate = self
        
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func image(for key: String) -> UIImage? {
        imageCache.object(forKey: key as NSString)?.image
    }

    func set(_ image: UIImage, for key: String) {
        // Calculate approximate memory cost (width * height * 4 bytes per pixel)
        let cost = Int(image.size.width * image.size.height * 4)
        let wrapper = ImageWrapper(image: image, key: key)
        imageCache.setObject(wrapper, forKey: key as NSString, cost: cost)
        cachedKeys.insert(key)
    }
    
    func remove(for key: String) {
        imageCache.removeObject(forKey: key as NSString)
        cachedKeys.remove(key)
    }
    
    func clearAll() {
        imageCache.removeAllObjects()
        cachedKeys.removeAll()
    }
    
    @objc private func handleMemoryWarning() {
        print("⚠️ Memory warning received - clearing avatar cache")
        clearAll()
    }
}

// MARK: - NSCacheDelegate
extension AvatarImageStore: NSCacheDelegate {
    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        // When NSCache evicts an object, remove its key from cachedKeys
        if let wrapper = obj as? ImageWrapper {
            Task { @MainActor in
                cachedKeys.remove(wrapper.key)
                print("🗑️ AvatarImageStore: Evicted image for key '\(wrapper.key)' due to memory pressure")
            }
        }
    }
} 